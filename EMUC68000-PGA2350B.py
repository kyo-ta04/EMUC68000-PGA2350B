# EMUC68000-PGA2350B 
from machine import Pin, PWM, Timer
import time, sys, select
import array
import micropython
from machine import mem32
# from micropython import const

def load_to_memory(memory, data, offset):
    """memoryの指定したoffset位置にdataをコピーする"""
    memory[offset : offset + len(data)] = data




SIO_BASE = 0xD0000000

# 値
OUT      = SIO_BASE + 0x10
OUT_SET  = SIO_BASE + 0x18
OUT_CLR  = SIO_BASE + 0x20

# 方向
OE       = SIO_BASE + 0x30
OE_SET   = SIO_BASE + 0x38
OE_CLR   = SIO_BASE + 0x40


# SIOレジスタのアドレスを定義
SIO_GPIO_IN    = const(0xd0000004)
SIO_GPIO_HI_IN = const(0xd0000008)
# ===== SIO レジスタ =====
SIO_BASE     = const(0xD0000000)
GPIO_IN      = const(SIO_BASE + 0x04)
GPIO_HI_IN   = const(SIO_BASE + 0x08)
GPIO_OUT_SET = const(SIO_BASE + 0x18)
GPIO_OUT_CLR = const(SIO_BASE + 0x20)
GPIO_OE_SET  = const(SIO_BASE + 0x38)
GPIO_OE_CLR  = const(SIO_BASE + 0x40)

DATA_MASK = const(0xFFFF)



# 値を格納するための32bit符号なし整数（'I'）の配列を事前に2個分確保
# [0]に下位32bit (GPIO 0-31), [1]に上位16bit (GPIO 32-47) を入れます
gpio_buffer = array.array('I', [0, 0])

# Viper関数：戻り値は返さず、引数で渡された配列のメモリを直接書き換える
@micropython.viper
def read_all_gpio(buf_ptr: ptr32):
    buf_ptr[0] = uint(ptr32(SIO_GPIO_IN)[0])     # GPIO 0-31 の値を読み出す
    buf_ptr[1] = uint(ptr32(SIO_GPIO_HI_IN)[0])  # GPIO 32-47 の値を読み出す


@micropython.viper
def data_bus_set_output(uds: int, lds: int, data: int):
    if (uds == 0):
        dm = 0xFF00
    else:
        dm = 0
    if (lds == 0):
        dm = dm | 0xFF
    mem32[GPIO_OUT_CLR] = dm
    mem32[GPIO_OUT_SET] = dm & data
    mem32[GPIO_OE_SET] = dm
    mem32[GPIO_OE_CLR] = 0xFFFF & ~(dm)

@micropython.viper
def data_bus_set_input():
#    """データバスを入力（ハイインピーダンス）にする"""
    mem32[GPIO_OE_CLR] = DATA_MASK

data_pins = [Pin(i, Pin.IN, Pin.PULL_UP) for i in range(0, 16)]     # D0-D15  in/out
adrs_pins = [Pin(i, Pin.IN, Pin.PULL_UP) for i in range(16, 39)]    # A1-A23 in
lds_pin = Pin(40, Pin.IN, Pin.PULL_UP) # GP40 in, LDS#
uds_pin = Pin(41, Pin.IN, Pin.PULL_UP) # GP41 in, UDS#
rw_pin = Pin(42, Pin.IN, Pin.PULL_UP)  # GP42 in, R/W#
as_pin = Pin(43, Pin.IN, Pin.PULL_UP)  # GP43 in, AS#
dtack_pin = Pin(44, Pin.OUT, value=0)  # GP44 out DTACK#
reset_pin = Pin(45, Pin.OUT, value=0)  # GP45 out RESET#
clk_pin = PWM(Pin(46), freq=10000, duty_u16=32768) # GP46 PWM CLK Hz

LDS_MASK = const(1 << (40 - 32))
UDS_MASK = const(1 << (41 -32))
RW_MASK = const(1 << (42 - 32))
AS_MASK = const(1 << (43 - 32))


# Simulate microcontroller memory with bytearray
MEMORY_SIZE = 65536 # 64KB memory
memory = bytearray(MEMORY_SIZE)

test1 = bytearray([
    0x00, 0x00, 0x00, 0x00,  # SP 0x0000
    0x00, 0x00, 0x00, 0x00,  # PC 0x0008
    0x4E, 0xF8, 0x00, 0x08   # 0008: JMP ($0008).W
    ])

# アドレス 0x0000 から 0x0015 までのメモリイメージ（計22バイト）
# 0x0000-0x0003: 初期スタックポインタ (仮に 0x00001000 と設定)
# 0x0004-0x0007: 初期PC (プログラム開始アドレス 0x00000008)
# 0x0008-0x0015: 作成した$4000番地の値をインクリメントするプログラム

test2 = bytearray([
    # ---- リセットベクトル領域 (0x0000 - 0x0007) ----
    0x00, 0x00, 0x10, 0x00,  # 0x1000: 初期SSP (0x00001000)
    0x00, 0x00, 0x00, 0x08,  # 0x0004: 初期PC  (0x00000008)
    
    # ---- プログラム領域 (0x0008 - 0x0015) ----
    0x41, 0xF8, 0x40, 0x00,  # 0x0008: LEA    $4000, A0
    0x10, 0x10,              # 0x000C: MOVE.B (A0), D0
    0x52, 0x00,              # 0x000E: ADDQ.B #1, D0
    0x10, 0x80,              # 0x0010: MOVE.B D0, (A0)
    0x4E, 0xF8, 0x00, 0x08   # 0x0012: JMP    $0008
])


# Hello World!
test3 = bytearray([
    0x00, 0x00, 0xA0, 0x00, 0x00, 0x00, 0x00, 0x08, 0x41, 0xFA, 0x00, 0x2C, 0x61, 0x00, 0x00, 0x1C, # 0x0000
    0x60, 0xFE, 0x48, 0x40, 0x10, 0x39, 0x00, 0x00, 0xE0, 0x01, 0xC0, 0x3C, 0x00, 0x02, 0x67, 0xF4, # 0x0010
    0x48, 0x40, 0x13, 0xC0, 0x00, 0x00, 0xE0, 0x00, 0x4E, 0x75, 0x10, 0x18, 0x67, 0x00, 0x00, 0x06, # 0x0020
    0x61, 0xE0, 0x60, 0xF6, 0x4E, 0x75, 0x0D, 0x0A, 0x20, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x4D, # 0x0030
    0x43, 0x36, 0x38, 0x30, 0x30, 0x38, 0x20, 0x57, 0x6F, 0x72, 0x6C, 0x64, 0x21, 0x0D, 0x0A, 0x0D, # 0x0040
    0x0A, 0x00                                                     # 0x0050
])


dump_high = [0] * 500
dump_low = [0] * 500

di = 0

# UART
ACIA_BASE = 0xE000
ACIAD = ACIA_BASE
ACIAC = ACIA_BASE + 1


@micropython.native
def bus_emu():
    ## 標準入力(sys.stdin)の監視設定
    spoll = select.poll()
    spoll.register(sys.stdin, select.POLLIN)

    global di
    s = 0; p = 0
    high = 0; low = 0
    ase = 0; rw = 0
    dm = 0
    start_time = time.ticks_ms()
    while True:
        read_all_gpio(gpio_buffer)
        high = gpio_buffer[1]; low = gpio_buffer[0]
        s = (high & 0x0F00)
        if (s != p):
            rw = int(high & RW_MASK)
            uds = int(high & UDS_MASK)
            lds = int(high & LDS_MASK)
            if ((uds == 0) or (lds == 0)):
                adrs = (((high & 0x7F) << 17) | (low >> 15)) & 0xFFFE
                data = int(low & 0xFFFF)
                if (rw):                    # Memory READ
                    if (adrs == ACIA_BASE):
                        if (lds == 0): # +1 ACIAC
                            data = (data & 0xFF00) | 0x02
                        if (uds == 0):
                            data = (data & 0xFF) | 0x4100
                    else:
                        if (uds == 0):
                            data = ((data & 0x00FF) | (memory[adrs] << 8))
                        if (lds == 0):
                            data = (data & 0xFF00) | memory[adrs + 1] 
                    data_bus_set_output(uds, lds, data)
                    low = (low & ~(0xFFFF)) | data
                else:                       # Memory WRITE
                    if ((adrs == ACIA_BASE) & (uds == 0)):
                        # data = data
                        print(chr(data & 0xFF), end="")
                    else:
                        if (uds == 0):
                            d = data >> 8
                            memory[adrs] = d
                        if (lds == 0):
                            d = data & 0xFF
                            memory[adrs + 1] = d

                if (di < 500) and (ase == 0):
                    dump_high[di] = high
                    dump_low[di] = low
                    di += 1
            else:
                data_bus_set_input()
            p = s
        if (10000 < time.ticks_diff(time.ticks_ms(), start_time)):
            reset_pin.value(0)
            break
        # 待ち時間0ミリ秒で入力イベントをチェック
        events = spoll.poll(0)
        if events:
            # 入力があれば1文字読み込む
            char = sys.stdin.read(1)
            print(f"入力された文字: {char}", end="")
            # 'q'が入力されたらループを抜ける
            if char == 'q':
                break
        time.sleep_us(0)
    

MC68K_CLK = 2000

def reset_off(t):
    print("RESET-OFF")
    print(f"MC68K_CLK = {MC68K_CLK / 1000:.3f}kHz..")
    clk_pin.freq(MC68K_CLK)
    time.sleep_ms(1)
    reset_pin.value(1)

print("Start..")
print("Load test3")
load_to_memory(memory, test3, 0x0000)

print("RESET-ON")
Timer().init(mode=Timer.ONE_SHOT, period=3000, callback=reset_off)
while (reset_pin.value() == 0):
    time.sleep(0)

bus_emu()
print("RESET-ON")
reset_pin.value(0)
time.sleep_ms(500)
print("CLK-OFF")
clk_pin.deinit()

LDS_M = 1 << 40
UDS_M = 1 << 41
RW_M = 1 << 42
AS_M = 1 << 43

for i in range(0, di):
#    d = dump_dat[i]
    d = (dump_high[i] << 32) | dump_low[i]
    lds = 1 if (d & LDS_M) else 0
    uds = 1 if (d & UDS_M) else 0
    rw = 1 if (d & RW_M) else 0
    ase = 1 if (d & AS_M) else 0
    adrs = ((d >> 16) & 0x7FFFFF) * 2
    data = d & 0xFFFF
    u = data >> 8
    l = data & 0xFF
    print(f"{i:04} U:{uds} L:{lds} RW:{rw} AS:{ase} {adrs:06X} {u:02X}-{l:02X}")
    time.sleep_ms(1)


print("END")



