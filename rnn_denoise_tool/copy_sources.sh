#!/bin/bash

# 设置源目录和目标目录
SRC_DIR="app/src/main/jni"
DST_DIR="rnn_denoise_tool/src"

# 创建目标目录（如果不存在）
mkdir -p "$DST_DIR"

# 需要复制的文件列表
FILES=(
    "rnnoise.c"
    "rnnoise.h"
    "rnn.c"
    "rnn.h"
    "rnn_data.c"
    "rnn_data.h"
    "pitch.c"
    "pitch.h"
    "kiss_fft.c"
    "kiss_fft.h"
    "_kiss_fft_guts.h"
    "celt_lpc.c"
    "celt_lpc.h"
    "common.h"
    "arch.h"
    "opus_types.h"
    "tansig_table.h"
)

# 复制文件
echo "Copying source files from $SRC_DIR to $DST_DIR"
for file in "${FILES[@]}"; do
    if [ -f "$SRC_DIR/$file" ]; then
        cp "$SRC_DIR/$file" "$DST_DIR/"
        echo "Copied: $file"
    else
        echo "Warning: $file not found in $SRC_DIR"
    fi
done

echo "Source files copied successfully!"
echo "You can now build the tool with 'cd rnn_denoise_tool && make'" 