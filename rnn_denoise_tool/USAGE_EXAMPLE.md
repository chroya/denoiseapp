# RNN降噪工具使用示例

本文档展示了如何使用RNN降噪工具处理音频文件的几个常用场景。

## 基本用法

处理单个WAV文件：

```bash
./denoise.sh input.wav output.wav
```

## 批量处理多个文件

以下是一个简单的Bash脚本，用于批量处理目录中的所有WAV文件：

```bash
#!/bin/bash

# 设置输入和输出目录
INPUT_DIR="./input_files"
OUTPUT_DIR="./output_files"

# 创建输出目录（如果不存在）
mkdir -p "$OUTPUT_DIR"

# 处理所有WAV文件
for input_file in "$INPUT_DIR"/*.wav; do
    if [ -f "$input_file" ]; then
        # 获取文件名（不包含路径）
        filename=$(basename "$input_file")
        
        # 设置输出文件路径
        output_file="$OUTPUT_DIR/${filename%.wav}_denoised.wav"
        
        echo "Processing: $filename"
        ./denoise.sh "$input_file" "$output_file"
    fi
done

echo "All files processed!"
```

将上述脚本保存为`batch_process.sh`，然后使其可执行：

```bash
chmod +x batch_process.sh
```

## 在管道中使用

如果您需要在更复杂的音频处理流程中使用本工具，可以结合其他命令行工具：

```bash
# 使用SoX转换立体声为单声道，然后降噪，再转换回立体声
sox stereo_input.wav -c 1 mono_temp.wav rate 48k
./denoise.sh mono_temp.wav denoised_mono.wav
sox denoised_mono.wav stereo_output.wav channels 2
rm mono_temp.wav denoised_mono.wav  # 清理临时文件
```

## 处理不同采样率的文件

尽管本工具最适合处理48kHz采样率的音频，但您可以使用SoX等工具进行采样率转换：

```bash
# 转换为48kHz，降噪，然后转换回原始采样率
original_rate=$(soxi -r input.wav)
sox input.wav -r 48000 temp_48k.wav
./denoise.sh temp_48k.wav denoised_48k.wav
sox denoised_48k.wav -r $original_rate output.wav
rm temp_48k.wav denoised_48k.wav  # 清理临时文件
```

## 视频音频处理示例

如果您需要处理视频文件中的音频，可以结合FFmpeg使用：

```bash
# 提取音频，降噪，然后替换原始音频
ffmpeg -i input_video.mp4 -vn -acodec pcm_s16le -ar 48000 -ac 1 extracted_audio.wav
./denoise.sh extracted_audio.wav denoised_audio.wav
ffmpeg -i input_video.mp4 -i denoised_audio.wav -c:v copy -map 0:v:0 -map 1:a:0 output_video.mp4
rm extracted_audio.wav denoised_audio.wav  # 清理临时文件
```

## 性能优化

对于非常长的音频文件，您可以分割处理以获得更好的性能：

```bash
# 分割成10分钟的片段，处理，然后合并
mkdir -p temp_segments denoised_segments
ffmpeg -i long_audio.wav -f segment -segment_time 600 -c copy temp_segments/segment_%03d.wav

for segment in temp_segments/*.wav; do
    segment_name=$(basename "$segment")
    ./denoise.sh "$segment" "denoised_segments/$segment_name"
done

# 合并处理后的片段
sox "denoised_segments/*.wav" denoised_long_audio.wav

# 清理临时文件
rm -rf temp_segments denoised_segments
```

## 常见问题解决

1. 如果出现"Invalid WAV file format"错误，请确保您的WAV文件是有效的16位PCM格式。
2. 如果处理后的音频质量不理想，请确保输入文件的采样率是48kHz。
3. 对于极低信噪比的录音，您可能需要多次应用降噪（但可能会导致语音失真）。 