cmake_minimum_required(VERSION 3.4.1)

# 禁用-Werror编译选项，避免将警告视为错误
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-error=deprecated-non-prototype -Wno-error")

# 添加RNNoise C语言源文件
add_library(denoise
            SHARED
            ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../src/rnnoise.c
            ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../src/rnn.c
            ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../src/rnn_data.c
            ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../src/pitch.c
            ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../src/kiss_fft.c
            ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../src/celt_lpc.c
            ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../src/denoise.c)

# 包含头文件目录
target_include_directories(denoise
                          PRIVATE
                          ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../src/)

# 设置编译参数 - 移除Werror以避免编译错误
target_compile_options(denoise PRIVATE -Wall)

# 链接系统库
find_library(log-lib log)
target_link_libraries(denoise ${log-lib}) 