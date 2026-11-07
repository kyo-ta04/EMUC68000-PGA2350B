// EMUC68000-PGA2350B
// MicroPython EMUC68000-PGA2350B.py の C SDK 移植。
// PGA2350 (RP2350B) が MC68000 の非同期バスを GPIO で受ける。
//
//   GPIO 0-15   D0-D15   in/out (pull-up, アイドル時は Hi-Z)
//   GPIO 16-38  A1-A23   in (pull-up)
//   GPIO 40     LDS#     in (pull-up)
//   GPIO 41     UDS#     in (pull-up)
//   GPIO 42     R/W#     in (pull-up)  H=Read L=Write
//   GPIO 43     AS#      in (pull-up)
//   GPIO 44     DTACK#   out, 常時 L (アサート)
//   GPIO 45     RESET#   out, 起動時 L
//   GPIO 46     CLK      PWM, 50%

#include <stdio.h>
#include <string.h>

#include "hardware/clocks.h"
#include "hardware/pwm.h"
#include "hardware/structs/sio.h"
#include "hardware/vreg.h"
#include "pico/stdio_usb.h"
#include "pico/stdlib.h"
#include "pico/multicore.h"
#include "tusb.h" // TinyUSB
#include "ehbasic.h"  // EhBASIC program image


#define PIN_LDS   40u
#define PIN_UDS   41u
#define PIN_RW    42u
#define PIN_AS    43u
#define PIN_DTACK 44u
#define PIN_RESET 45u
#define PIN_CLK   46u

#define LDS_MASK (1u << (PIN_LDS - 32u))
#define UDS_MASK (1u << (PIN_UDS - 32u))
#define RW_MASK  (1u << (PIN_RW - 32u))
#define AS_MASK  (1u << (PIN_AS - 32u))
#define DTACK_MASK (1u << (PIN_DTACK - 32u))
#define CTRL_MASK (LDS_MASK | UDS_MASK | RW_MASK | AS_MASK)
#define DS_MASK  (LDS_MASK | UDS_MASK)

#define DATA_MASK 0xFFFFu

// #define ACIA_BASE 0x00E000u
#define ACIA_BASE 0x80E000u
#define ACIAD     ACIA_BASE
#define ACIAC     (ACIA_BASE + 1u)

// #define MEMORY_SIZE 65536u
// #define MEMADRS_MASK 0xFFFFu

// #define MEMORY_SIZE 131072u 262,144
// #define MEMADRS_MASK 0x1FFFFu

#define MEMORY_SIZE 262144u     // 256KByte
#define MEMADRS_MASK 0x3FFFFu

#define DUMP_MAX    500
#define MC68K_CLK   6000000u
#define CLK_BOOT_HZ 100000u

// 0 番地に載せるイメージ。1=test1, 2=test2, 3=test3, 4=test4
#ifndef TEST_SELECT
#define TEST_SELECT 5
#endif



// 68000 memory emulation area (64KB) aligned to 64KB boundary for performance
static uint8_t __attribute__((aligned(65536))) __not_in_flash("bus_memory")  memory[MEMORY_SIZE];

static uint32_t dump_high[DUMP_MAX];
static uint32_t dump_low[DUMP_MAX];
static int di;

// SSP=0, PC=0。0x0008 で JMP $0008 を繰り返す
static const uint8_t test1[] = {
    0x00, 0x00, 0x00, 0x00,  // SP 0x0000
    0x00, 0x00, 0x00, 0x00,  // PC 0x0008
    0x4E, 0xF8, 0x00, 0x08   // 0008: JMP ($0008).W
};

// $4000 のバイトをインクリメントして 0x0008 に戻る
static const uint8_t test2[] = {
    // リセットベクトル (0x0000-0x0007)
    0x00, 0x00, 0x10, 0x00,  // 0x0000: 初期SSP 0x00001000
    0x00, 0x00, 0x00, 0x08,  // 0x0004: 初期PC  0x00000008
    // プログラム (0x0008-0x0015)
    0x41, 0xF8, 0x40, 0x00,  // 0x0008: LEA    $4000, A0
    0x10, 0x10,              // 0x000C: MOVE.B (A0), D0
    0x52, 0x00,              // 0x000E: ADDQ.B #1, D0
    0x10, 0x80,              // 0x0010: MOVE.B D0, (A0)
    0x4E, 0xF8, 0x00, 0x08   // 0x0012: JMP    $0008
};

// Hello MC68008 World (リセットベクタ + putc/puts)
static const uint8_t test3[] = {
    // 0x0000: リセットベクトル領域
    0x00, 0x00, 0xA0, 0x00,                         // 0x0000: 初期SSP ($0000A000)
    0x00, 0x00, 0x00, 0x08,                         // 0x0004: 初期PC ($00000008)
    
    // 0x0008: メインプログラム領域
    0x41, 0xFA, 0x00, 0x2C,                         // 0x0008: LEA MSG(PC), A0  (PC+$002C = 0x0036)
    0x61, 0x00, 0x00, 0x1C,                         // 0x000C: BSR.W PUTS       (PC+$001C = 0x002A)
    0x60, 0xFE,                                     // 0x0010: BRA.S *          (無限ループ)
    
    // 0x0012: 1文字出力サブルーチン (PUTCHAR)
    0x48, 0x40,                                     // 0x0012: SWAP D0          (送信文字を上位ワードへ退避)
    0x10, 0x39, 0x00, 0x80, 0xE0, 0x01,             // 0x0014: MOVE.B $80E001, D0 (ステータスレジスタ)
    0xC0, 0x3C, 0x00, 0x02,                         // 0x001A: AND.B #$02, D0   (TDREチェック)
    0x67, 0xF4,                                     // 0x001E: BEQ.S WAIT_TX    (-12バイト = 0x0014)
    0x48, 0x40,                                     // 0x0020: SWAP D0          (送信文字を下位バイトへ復帰)
    0x13, 0xC0, 0x00, 0x80, 0xE0, 0x00,             // 0x0022: MOVE.B D0, $80E000 (データ送信)
    0x4E, 0x75,                                     // 0x0028: RTS
    
    // 0x002A: 文字列出力サブルーチン (PUTS)
    0x10, 0x18,                                     // 0x002A: MOVE.B (A0)+, D0
    0x67, 0x00, 0x00, 0x06,                         // 0x002C: BEQ.W PUTS_END   (PC+$0006 = 0x0034)
    0x61, 0xE0,                                     // 0x0030: BSR.S PUTCHAR    (-32バイト = 0x0012)
    0x60, 0xF6,                                     // 0x0032: BRA.S PUTS       (-10バイト = 0x002A)
    0x4E, 0x75,                                     // 0x0034: RTS
    
    // 0x0036: 文字列データ領域 (MSG)
    0x0D, 0x0A,                                     // 0x0036: CR, LF
    0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x4D, 0x43, // 0x0038: "Hello MC"
    0x36, 0x38, 0x30, 0x30, 0x38, 0x20, 0x57, 0x6F, // 0x0040: "68008 Wo"
    0x72, 0x6C, 0x64, 0x21,                         // 0x0048: "rld!"
    0x0D, 0x0A, 0x0D, 0x0A,                         // 0x004C: CR, LF, CR, LF
    0x00                                            // 0x0050: ヌル終端文字
};

// ACIA ループバック。$80E001 bit0(RDRF) を待って $80E000 を読み、
// bit1(TDRE) を待って同じバイトを $80E000 へ書く。
static const uint8_t test4[] = {
    0x00, 0x00, 0xA0, 0x00,              // 0x0000: 初期SSP 0x0000A000
    0x00, 0x00, 0x00, 0x08,              // 0x0004: 初期PC  0x00000008
    0x10, 0x39, 0x00, 0x80, 0xE0, 0x01,  // 0x0008: MOVE.B $80E001, D0
    0x02, 0x00, 0x00, 0x01,              // 0x000E: ANDI.B #1, D0
    0x67, 0xF4,                          // 0x0012: BEQ.S  $800008
    0x10, 0x39, 0x00, 0x80, 0xE0, 0x00,  // 0x0014: MOVE.B $80E000, D0
    0x12, 0x39, 0x00, 0x80, 0xE0, 0x01,  // 0x001A: MOVE.B $80E001, D1
    0x02, 0x01, 0x00, 0x02,              // 0x0020: ANDI.B #2, D1
    0x67, 0xF4,                          // 0x0024: BEQ.S  $001A
    0x13, 0xC0, 0x00, 0x80, 0xE0, 0x00,  // 0x0026: MOVE.B D0, $80E000
    0x60, 0xDA                           // 0x002C: BRA.S  $0008
};

static void load_to_memory(const uint8_t *data, size_t len, uint32_t offset) {
    if (offset >= MEMORY_SIZE) {
        return;
    }
    if (offset + len > MEMORY_SIZE) {
        len = MEMORY_SIZE - offset;
    }
    memcpy(memory + offset, data, len);
}

static const uint8_t *selected_test(size_t *len, const char **name) {
    switch (TEST_SELECT) {
    case 1:
        *len = sizeof test1;
        *name = "test1";
        return test1;
    case 2:
        *len = sizeof test2;
        *name = "test2";
        return test2;
    case 3:
        *len = sizeof test3;
        *name = "test3";
        return test3;
    case 4:
        *len = sizeof test4;
        *name = "test4";
        return test4;
    case 5:
        *len = ehbasic_size;
        *name = "EhBASIC";
        return EhBASIC;
    default:
        *len = sizeof test3;
        *name = "test3";
        return test3;
    }
}

static void pin_input(uint pin) {
    gpio_init(pin);
    gpio_set_dir(pin, GPIO_IN);
}


static void pin_input_pullup(uint pin) {
    gpio_init(pin);
    gpio_set_dir(pin, GPIO_IN);
    gpio_pull_up(pin);
}

static void pin_output_low(uint pin) {
    gpio_init(pin);
    gpio_put(pin, 0);
    gpio_set_dir(pin, GPIO_OUT);
}

static void pin_output_high(uint pin) {
    gpio_init(pin);
    gpio_put(pin, 1);
    gpio_set_dir(pin, GPIO_OUT);
}

// 50% PWM。GPIO46 は RP2350B の PWM slice 11 ch A。
static void clk_set_hz(uint32_t freq_hz) {
    uint slice = pwm_gpio_to_slice_num(PIN_CLK);
    uint chan = pwm_gpio_to_channel(PIN_CLK);
    uint32_t sys = clock_get_hz(clk_sys);
    uint32_t div = 1;
    uint32_t top = sys / freq_hz;

    while (top > 65536u && div < 255u) {
        div++;
        top = sys / (freq_hz * div);
    }
    if (top < 2u) {
        top = 2u;
    }

    pwm_set_clkdiv_int_frac(slice, (uint8_t)div, 0);
    pwm_set_wrap(slice, (uint16_t)(top - 1u));
    pwm_set_chan_level(slice, chan, (uint16_t)(top / 2u));
    pwm_set_enabled(slice, true);
}

static void clk_start(void) {
    gpio_set_function(PIN_CLK, GPIO_FUNC_PWM);
    clk_set_hz(CLK_BOOT_HZ);
}

static void clk_stop(void) {
    uint slice = pwm_gpio_to_slice_num(PIN_CLK);
    pwm_set_enabled(slice, false);
    gpio_set_function(PIN_CLK, GPIO_FUNC_SIO);
    gpio_set_dir(PIN_CLK, GPIO_IN);
}

// Python の data_bus_set_output と同じ順序。
// uds/lds はマスク値そのもの (0 ならそのレーンがアサート)。
static inline void data_bus_set_output(uint32_t uds, uint32_t lds, uint32_t data) {
    uint32_t dm = 0;
    if (uds == 0) {
        dm = 0xFF00u;
    }
    if (lds == 0) {
        dm |= 0x00FFu;
    }
    sio_hw->gpio_clr = dm;
    sio_hw->gpio_set = dm & data;
    sio_hw->gpio_oe_set = dm;
    sio_hw->gpio_oe_clr = DATA_MASK & ~dm;
}

static inline void data_bus_set_input(void) {
    sio_hw->gpio_oe_clr = DATA_MASK;
}

//  USB CDC へ出す。
static void acia_output_usb(uint8_t ch) {
    if (!stdio_usb_connected()) {
        return;
    }
    putchar_raw((int)ch);
    stdio_flush();
}

// GPIO16-31 が A1-A16、GPIO32-38 が A17-A23。
static inline uint32_t bus_address(uint32_t high, uint32_t low) {
    return (((high & 0x7Fu) << 17) | (low >> 15)) & 0x00FFFFFEu;
}

// GPIO0-31 と GPIO32-47 を読む。__force_inline なので呼び出しには残らず、
// その場の2本のロードになる。
__force_inline static void read_all_gpio(uint32_t *low, uint32_t *high) {
    *low = sio_hw->gpio_in;
    *high = sio_hw->gpio_hi_in;
}

// DTACK direct SIO control (for speed in busemu)
static inline void dtack_low(void)  { sio_hw->gpio_out = sio_hw->gpio_out & ~DTACK_MASK; }  // assert (active low)
static inline void dtack_high(void) { sio_hw->gpio_out = sio_hw->gpio_out |  DTACK_MASK; }  // deassert (high)


// 通信専用のコア0,1で共有するUART通信のためのグローバル変数
static volatile uint8_t __attribute__((section(".scratch_x"))) uart_tx_data; // 送信データバッファ(Z80からPicoへ: 1バイト)
static volatile uint8_t __attribute__((section(".scratch_x"))) uart_rx_data; // 受信データバッファ(PicoからZ80へ: 1バイト)
static volatile bool __attribute__((section(".scratch_x"))) uart_tx_ready; // 送信可フラグ (true=Ready, false=Busy)
static volatile bool __attribute__((section(".scratch_x"))) uart_rx_ready; // 受信完了フラグ (true=Ready, false=Empty)
static volatile bool __attribute__((section(".scratch_x"))) exit_flag = false;
static volatile bool reset_off_requested = false;


void __time_critical_func(bus_emu(void)) {
    uart_tx_data = 0;      // 送信データ初期化
    uart_rx_data = 0;      // 受信データ初期化
    uart_tx_ready = true;  // 送信準備完了
    uart_rx_ready = false; // 受信バッファは空
    exit_flag = false;     // 終了フラグ初期化

    absolute_time_t start = get_absolute_time();
    uint32_t prev = 0;

    while (true) {
        uint32_t low;
        uint32_t high;
        read_all_gpio(&low, &high);
        uint32_t s = high & CTRL_MASK;

        if (s != prev) {
            uint32_t rw = high & RW_MASK;
            uint32_t uds = high & UDS_MASK;
            uint32_t lds = high & LDS_MASK;
            if ((uds == 0) || (lds == 0)) {
                uint32_t adrs = bus_address(high, low);
                // uint16_t ad = (uint16_t)adrs; // 64KBメモリー領域は下位16bitでミラー
                uint32_t ad = (adrs & MEMADRS_MASK); // 256KBメモリー領域は下位18bitでミラー
                uint32_t data = low & DATA_MASK;
                if (adrs != ACIA_BASE) {  // I/O は全アドレスで判定
                // if (ad != ACIA_BASE) {  // I/O 16bit アドレスで判定
                    if (rw) {           //  READ メモリー
                        if (uds == 0) {
                            data = (data & 0x00FFu) | ((uint32_t)memory[ad] << 8);
                        }
                        if (lds == 0) {
                            data = (data & 0xFF00u) | memory[ad + 1u];
                        }
                        data_bus_set_output(uds, lds, data);
                        low = (low & ~DATA_MASK) | data;
                    } else {            //  WRITE メモリー
                        if (uds == 0) {
                            memory[ad] = (uint8_t)(data >> 8);
                        }
                        if (lds == 0) {
                            memory[ad + 1u] = (uint8_t)(data & 0xFFu);
                        }
                    }
                } else {    // I/O アクセス
                    if (rw) { // READ ACIA
                        // LDS: ACIAC ($E001) status TDRE RDRF. UDS: ACIAD ($E000)
                        if (lds == 0) { // ACIC $E001
                            uint8_t r = uart_rx_ready ? 0x01 : 0x00;  // RDRF
                            r |= uart_tx_ready ? 0x02 : 0x00;         // TDRE
                            data = (data & 0xFF00u) | r;
                        }
                        if (uds == 0) { // UDS: ACIAD ($E000) RX data
                            uint32_t r = uart_rx_ready ? ((uint32_t)uart_rx_data << 8) : 0;
                            uart_rx_ready = false;  // consume the char
                            data = (data & 0x00FFu) | r;
                        }
                        data_bus_set_output(uds, lds, data);
                        low = (low & ~DATA_MASK) | data;
                    } else { // WRITE ACIA
                        if (uds == 0) {
                        // acia_output_usb(data);
                            if (uart_tx_ready) {       // 送信可能な場合のみ送信データを格納
                                uart_tx_data = (data >> 8);
                                uart_tx_ready = false; // mark as busy
                            }
                        }
                    }
                }
                if (false) {
                    if (di < DUMP_MAX) {
                        dump_high[di] = high;
                        dump_low[di] = low;
                        di++;
                    }
                }
            } else {
                data_bus_set_input();
            }
            prev = s;
        }
        if (exit_flag) {
            break;  // exit on Ctrl-\ from UART
        }
        if (false) {
            if (absolute_time_diff_us(start, get_absolute_time()) > 5000 * 1000) {
                gpio_put(PIN_RESET, 0);
                break;
            }
        }
/*
        if (!uart_tx_ready) {
            acia_output_usb(uart_tx_data);
            uart_tx_ready = true; // 送信完了（readyに戻す）
        }
        if (!uart_rx_ready) {
            int ch = getchar_timeout_us(0);
            if (ch >= 0) {
                if (ch == 0x1C) { // Ctrl-\で終了
                    break;
                }
                uart_rx_data = (uint8_t)ch;
                uart_rx_ready = true;
            }
        }
*/
        tight_loop_contents();
    }
}


static void reset_off(void);


//
// --- UART Task (Core 0) ---
//
void uart_task(void) {
    printf("task UART start - Core0\n\n");
    while (true) {
        if (reset_off_requested) {
            reset_off_requested = false;
            reset_off();
        }
        if (!uart_tx_ready) {
            acia_output_usb(uart_tx_data);
            uart_tx_ready = true; // 送信完了（readyに戻す）
        }
        if (!uart_rx_ready) {
            int ch = getchar_timeout_us(0);
            if (ch >= 0) {
                if (ch == 0x1C) { // Ctrl-\で終了
                    break;
                }
                uart_rx_data = (uint8_t)ch;
                uart_rx_ready = true;
            }
        }
        sleep_us(500); // 500us待機（CPU負荷を下げるため）
    }
    exit_flag = true;
}


static void reset_off(void) {
    printf("RESET-OFF\n");
    printf("MC68K_CLK = %.3fkHz..\n", MC68K_CLK / 1000.0);
    clk_set_hz(MC68K_CLK);
    sleep_ms(1);
    gpio_put(PIN_RESET, 1);
}

static int64_t reset_off_alarm_callback(alarm_id_t id, void *user_data) {
    (void)id;
    (void)user_data;
    reset_off_requested = true;
    return 0;
}

static void dump_trace(void) {
    for (int i = 0; i < di; i++) {
        uint64_t d = ((uint64_t)dump_high[i] << 32) | dump_low[i];
        int lds = (d & (1ull << PIN_LDS)) ? 1 : 0;
        int uds = (d & (1ull << PIN_UDS)) ? 1 : 0;
        int rw = (d & (1ull << PIN_RW)) ? 1 : 0;
        int ase = (d & (1ull << PIN_AS)) ? 1 : 0;
        uint32_t adrs = (uint32_t)(((d >> 16) & 0x7FFFFFu) * 2u);
        unsigned u = (unsigned)((d >> 8) & 0xFFu);
        unsigned l = (unsigned)(d & 0xFFu);
        printf("%04d U:%d L:%d RW:%d AS:%d %06lX %02X-%02X\n",
               i, uds, lds, rw, ase, (unsigned long)adrs, u, l);
        sleep_ms(1);
    }
}


int main(void) {
    vreg_set_voltage(VREG_VOLTAGE_1_30);
    sleep_ms(10);
    set_sys_clock_khz(300000, true);

    stdio_init_all();

    for (uint pin = 0; pin < 16; pin++) {
        pin_input_pullup(pin);
    }
    for (uint pin = 16; pin <= 38; pin++) {
        pin_input_pullup(pin);
    }
    pin_input_pullup(PIN_LDS);
    pin_input_pullup(PIN_UDS);
    pin_input_pullup(PIN_RW);
    pin_input_pullup(PIN_AS);
    pin_output_low(PIN_DTACK);
    pin_output_low(PIN_RESET);
    clk_start();

    absolute_time_t usb_deadline = make_timeout_time_ms(2000);
    while (!stdio_usb_connected() && !time_reached(usb_deadline)) {
        sleep_ms(10);
    }

    printf("EMUC68000-PGA2350B Rev0.0\n");
    printf("ACIAD: %06X, ACIAC: %06X\n", ACIAD, ACIAC);
    printf("MEMORY: %d Byte\n", MEMORY_SIZE);
    printf("Start..\n");
    size_t test_len = 0;
    const char *test_name = "test3";
    const uint8_t *test_image = selected_test(&test_len, &test_name);
    printf("Load %s\n", test_name);
    load_to_memory(test_image, test_len, 0x0000);

    printf("RESET-ON\n");
    sleep_ms(1);
    printf("ROMエミュレータ起動 - Core1\n");
    multicore_launch_core1(bus_emu);
    sleep_ms(1);
    if (add_alarm_in_ms(2000, reset_off_alarm_callback, NULL, false) < 0) {
        panic("Failed to schedule RESET-OFF alarm");
    }
    uart_task();

    printf("RESET-ON\n");
    gpio_put(PIN_RESET, 0);
    sleep_ms(500);
    printf("CLK-OFF\n");
    clk_stop();

    if (true) {
        dump_trace();
    }
    printf("END\n");
    while (true) {
        tight_loop_contents();
        sleep_ms(1000);
    }
}
