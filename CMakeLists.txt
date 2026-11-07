# Generated Cmake Pico project file

cmake_minimum_required(VERSION 3.13)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Initialise pico_sdk from installed location
# (note this can come from environment, CMake cache etc)

# == DO NOT EDIT THE FOLLOWING LINES for the Raspberry Pi Pico VS Code Extension to work ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()
set(sdkVersion 2.3.1)
set(toolchainVersion 15_2_Rel1)
set(picotoolVersion 2.3.1)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================
set(PICO_BOARD pimoroni_pga2350 CACHE STRING "Board type")

# Pull in Raspberry Pi Pico SDK (must be before project)
include(pico_sdk_import.cmake)

project(EMUC68000-PGA2350B C CXX ASM)

# Initialise the Raspberry Pi Pico SDK
pico_sdk_init()

# Add executable. Default name is the project name, version 0.1

add_executable(EMUC68000-PGA2350B EMUC68000-PGA2350B.c ehbasic.c)

pico_set_program_name(EMUC68000-PGA2350B "EMUC68000-PGA2350B")
pico_set_program_version(EMUC68000-PGA2350B "0.1")

# Modify the below lines to enable/disable output over UART/USB
# UART is disabled because it conflicts with D0/D1 (GPIO0/1).
pico_enable_stdio_uart(EMUC68000-PGA2350B 0)
pico_enable_stdio_usb(EMUC68000-PGA2350B 1)

# Add the standard library to the build
target_link_libraries(EMUC68000-PGA2350B
        pico_stdlib
        pico_multicore)

# Add the standard include files to the build
target_include_directories(EMUC68000-PGA2350B PRIVATE
        ${CMAKE_CURRENT_LIST_DIR}
)

# Add any user requested libraries
target_link_libraries(EMUC68000-PGA2350B
        hardware_pwm
        hardware_clocks
        hardware_vreg
        )

pico_add_extra_outputs(EMUC68000-PGA2350B)
