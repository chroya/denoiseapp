#!/bin/bash

# 音频预处理脚本
# 将各种音频格式转换为适合RNN降噪处理的WAV格式
# 用法: ./convert_audio.sh <输入文件> <输出WAV文件>

# 检查是否安装了FFmpeg
command -v ffmpeg >/dev/null 2>&1 || { 
    echo "错误: 需要安装FFmpeg才能转换音频格式"; 
    echo "请访问 https://ffmpeg.org/download.html 下载并安装FFmpeg"; 
    exit 1; 
}

# 检查参数
if [ $# -ne 2 ]; then
    echo "用法: $0 <输入文件> <输出WAV文件>"
    echo ""
    echo "此脚本将各种音频格式转换为适合RNN降噪处理的WAV格式："
    echo "- 16位PCM"
    echo "- 单声道(mono)"
    echo "- 48kHz采样率"
    echo ""
    echo "示例:"
    echo "  $0 input.mp3 output.wav      # 将MP3转换为WAV"
    echo "  $0 stereo.wav mono_48k.wav   # 将立体声WAV转换为单声道48kHz"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"

# 检查输入文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    echo "错误: 输入文件不存在: $INPUT_FILE"
    exit 1
fi

# 检查输出文件扩展名
if [[ "$OUTPUT_FILE" != *.wav ]]; then
    echo "警告: 输出文件应当使用.wav扩展名"
    OUTPUT_FILE="${OUTPUT_FILE}.wav"
    echo "已将输出文件名修改为: $OUTPUT_FILE"
fi

# 获取输入文件信息
echo "分析输入文件: $INPUT_FILE"
FILE_INFO=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,channels,sample_rate,bit_depth -of default=noprint_wrappers=1 "$INPUT_FILE" 2>&1)

echo "文件信息:"
echo "$FILE_INFO"
echo ""

# 执行转换
echo "开始转换音频格式..."
echo "- 目标格式: 16位PCM，单声道，48kHz采样率"

ffmpeg -v warning -i "$INPUT_FILE" -vn -acodec pcm_s16le -ac 1 -ar 48000 "$OUTPUT_FILE"

# 检查转换结果
if [ $? -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
    # 获取转换后的文件大小
    OUTPUT_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    
    echo ""
    echo "✓ 转换成功!"
    echo "- 输出文件: $OUTPUT_FILE"
    echo "- 文件大小: $OUTPUT_SIZE"
    echo ""
    echo "现在您可以使用以下命令进行降噪处理:"
    echo "./denoise.sh \"$OUTPUT_FILE\" \"${OUTPUT_FILE%.wav}_denoised.wav\""
else
    echo ""
    echo "✗ 转换失败!"
    echo "请检查输入文件格式是否受支持，或尝试使用其他转换工具。"
fi 