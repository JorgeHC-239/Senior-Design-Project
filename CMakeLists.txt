cmake_minimum_required(VERSION 3.13)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# == DO NOT EDIT THE FOLLOWING LINES for the Raspberry Pi Pico VS Code Extension to work ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()
set(sdkVersion 2.1.1)
set(toolchainVersion 14_2_Rel1)
set(picotoolVersion 2.1.1)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================

set(PICO_BOARD pico2 CACHE STRING "Board type")

# Pull in Raspberry Pi Pico SDK (must be before project)
include(pico_sdk_import.cmake)

project(UserInterfaceCode C CXX ASM)

# Initialise the Raspberry Pi Pico SDK
pico_sdk_init()

# Add your source file
add_executable(UserInterfaceCode
    UserInterfaceCode.cpp
)

# Set program metadata
pico_set_program_name(UserInterfaceCode "UserInterfaceCode")
pico_set_program_version(UserInterfaceCode "0.1")

# Enable/disable standard IO
pico_enable_stdio_uart(UserInterfaceCode 0)
pico_enable_stdio_usb(UserInterfaceCode 0)

# Link libraries for UART and I2C functionality
target_link_libraries(UserInterfaceCode
    pico_stdlib
    hardware_uart
    hardware_i2c
)

# Add include directory (if needed)
target_include_directories(UserInterfaceCode PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}
)

# Create UF2 and binary file
pico_add_extra_outputs(UserInterfaceCode)
