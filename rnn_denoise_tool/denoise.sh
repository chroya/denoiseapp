#!/bin/bash

# RNN降噪工具封装脚本
# 用法: ./denoise.sh input.wav output.wav

# 检查参数
if [ $# -ne 2 ]; then
    echo "Usage: $0 <input.wav> <output.wav>"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"

# 检查输入文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

# 检查文件扩展名
if [[ "$INPUT_FILE" != *.wav ]]; then
    echo "Error: Input file must be a WAV file"
    exit 1
fi

if [[ "$OUTPUT_FILE" != *.wav ]]; then
    echo "Warning: Output file should have .wav extension"
    OUTPUT_FILE="$OUTPUT_FILE.wav"
fi

# 脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 运行降噪工具
echo "Running RNN denoising on: $INPUT_FILE"
echo "Output will be saved to: $OUTPUT_FILE"

# 调用降噪程序
"$SCRIPT_DIR/rnn_denoise" "$INPUT_FILE" "$OUTPUT_FILE"

# 检查执行状态
if [ $? -eq 0 ]; then
    echo "Denoising completed successfully!"
else
    echo "Error occurred during denoising"
    exit 1
fi

# 显示文件信息
echo ""
echo "Original file size: $(du -h "$INPUT_FILE" | cut -f1)"
echo "Denoised file size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""
echo "Done." 