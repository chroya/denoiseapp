#!/bin/bash

# RNN降噪工具批处理脚本
# 用法: ./batch_process.sh <输入目录> <输出目录>

# 检查参数
if [ $# -ne 2 ]; then
    echo "Usage: $0 <input_directory> <output_directory>"
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"

# 检查输入目录是否存在
if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory not found: $INPUT_DIR"
    exit 1
fi

# 创建输出目录（如果不存在）
mkdir -p "$OUTPUT_DIR"

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 计数器
total_files=0
processed_files=0
skipped_files=0

# 处理所有WAV文件
echo "Starting batch processing..."
echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo ""

for input_file in "$INPUT_DIR"/*.wav; do
    if [ -f "$input_file" ]; then
        ((total_files++))
        
        # 获取文件名（不包含路径）
        filename=$(basename "$input_file")
        
        # 设置输出文件路径
        output_file="$OUTPUT_DIR/${filename%.wav}_denoised.wav"
        
        echo "[$processed_files/$total_files] Processing: $filename"
        
        # 调用降噪脚本
        "$SCRIPT_DIR/denoise.sh" "$input_file" "$output_file"
        
        # 检查执行状态
        if [ $? -eq 0 ]; then
            echo "✓ Successfully processed: $filename"
            ((processed_files++))
        else
            echo "✗ Failed to process: $filename"
            ((skipped_files++))
        fi
        
        echo ""
    fi
done

echo "Batch processing completed!"
echo "Total files: $total_files"
echo "Successfully processed: $processed_files"
echo "Failed/skipped: $skipped_files" 