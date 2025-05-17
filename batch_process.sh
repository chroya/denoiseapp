#!/bin/bash

# RNN降噪工具批处理脚本
# 用法: ./batch_process.sh <输入目录> <输出目录>

# 检查参数
if [ $# -ne 2 ]; then
    echo "用法: $0 <输入目录> <输出目录>"
    echo ""
    echo "示例:"
    echo "  $0 ./input_wavs ./output_wavs     # 处理input_wavs目录中的所有WAV文件"
    echo "  $0 ./samples ./results            # 处理samples目录中的WAV文件并输出到results目录"
    echo ""
    echo "测试单个文件:"
    echo "  ./denoise.sh input.wav output.wav # 处理单个WAV文件"
    
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"

# 检查输入目录是否存在
if [ ! -d "$INPUT_DIR" ]; then
    echo "错误: 输入目录不存在: $INPUT_DIR"
    echo "请先创建输入目录并放入WAV文件"
    exit 1
fi

# 检查目录中是否有WAV文件
WAV_COUNT=$(find "$INPUT_DIR" -name "*.wav" | wc -l)
if [ "$WAV_COUNT" -eq 0 ]; then
    echo "警告: 在 $INPUT_DIR 中没有找到WAV文件"
    echo "请确保WAV文件扩展名为小写(.wav而不是.WAV)"
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
echo "开始批量处理..."
echo "输入目录: $INPUT_DIR"
echo "输出目录: $OUTPUT_DIR"
echo "找到 $WAV_COUNT 个WAV文件"
echo ""

for input_file in "$INPUT_DIR"/*.wav; do
    if [ -f "$input_file" ]; then
        ((total_files++))
        
        # 获取文件名（不包含路径）
        filename=$(basename "$input_file")
        
        # 设置输出文件路径
        output_file="$OUTPUT_DIR/${filename%.wav}_denoised.wav"
        
        echo "[$processed_files/$total_files] 处理: $filename"
        
        # 调用降噪脚本
        "$SCRIPT_DIR/denoise.sh" "$input_file" "$output_file"
        
        # 检查执行状态
        if [ $? -eq 0 ]; then
            echo "✓ 成功处理: $filename"
            ((processed_files++))
        else
            echo "✗ 处理失败: $filename"
            ((skipped_files++))
        fi
        
        echo ""
    fi
done

echo "批处理完成!"
echo "总文件数: $total_files"
echo "成功处理: $processed_files"
echo "处理失败: $skipped_files"

if [ $processed_files -gt 0 ]; then
    echo ""
    echo "处理后的文件保存在: $OUTPUT_DIR"
fi 