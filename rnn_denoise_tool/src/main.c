#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rnnoise.h"

#define FRAME_SIZE 480  // 10ms at 48kHz

// WAVE 文件常量
#define RIFF_ID 0x46464952  // "RIFF" in little endian
#define WAVE_ID 0x45564157  // "WAVE" in little endian
#define FMT_ID  0x20746d66  // "fmt " in little endian
#define DATA_ID 0x61746164  // "data" in little endian

// 读取4字节整数（小端序）
unsigned int read_uint32(FILE *fp) {
    unsigned char buffer[4];
    fread(buffer, 1, 4, fp);
    return buffer[0] | (buffer[1] << 8) | (buffer[2] << 16) | (buffer[3] << 24);
}

// 读取2字节整数（小端序）
unsigned short read_uint16(FILE *fp) {
    unsigned char buffer[2];
    fread(buffer, 1, 2, fp);
    return buffer[0] | (buffer[1] << 8);
}

// 写入4字节整数（小端序）
void write_uint32(FILE *fp, unsigned int value) {
    unsigned char buffer[4];
    buffer[0] = value & 0xFF;
    buffer[1] = (value >> 8) & 0xFF;
    buffer[2] = (value >> 16) & 0xFF;
    buffer[3] = (value >> 24) & 0xFF;
    fwrite(buffer, 1, 4, fp);
}

// 写入2字节整数（小端序）
void write_uint16(FILE *fp, unsigned short value) {
    unsigned char buffer[2];
    buffer[0] = value & 0xFF;
    buffer[1] = (value >> 8) & 0xFF;
    fwrite(buffer, 1, 2, fp);
}

// WAV 文件信息结构
typedef struct {
    // 文件格式信息
    unsigned int sample_rate;      // 采样率
    unsigned short num_channels;    // 通道数
    unsigned short bits_per_sample; // 每个样本的位数
    
    // 文件位置信息
    unsigned int data_offset;       // 数据块开始位置
    unsigned int data_size;         // 数据块大小（字节）
} WavInfo;

// 读取WAV文件头并提取信息
int read_wav_header(FILE *fp, WavInfo *info) {
    unsigned int chunk_id, chunk_size, format, subchunk_id, subchunk_size;
    unsigned short audio_format, num_channels, block_align, bits_per_sample;
    unsigned int sample_rate, byte_rate;
    
    // 保存文件开始位置
    long initial_pos = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    
    // 读取RIFF头
    chunk_id = read_uint32(fp);
    chunk_size = read_uint32(fp);  // 整个文件大小 - 8
    format = read_uint32(fp);      // "WAVE"
    
    if (chunk_id != RIFF_ID || format != WAVE_ID) {
        fprintf(stderr, "Error: Not a valid WAVE file\n");
        return 0;
    }
    
    // 找到并读取fmt块
    while (1) {
        subchunk_id = read_uint32(fp);
        subchunk_size = read_uint32(fp);
        
        if (subchunk_id == FMT_ID) {
            // 读取格式信息
            audio_format = read_uint16(fp);    // 1表示PCM
            num_channels = read_uint16(fp);    // 通道数
            sample_rate = read_uint32(fp);     // 采样率
            byte_rate = read_uint32(fp);       // 每秒字节数
            block_align = read_uint16(fp);     // 块对齐
            bits_per_sample = read_uint16(fp); // 每样本位数
            
            // 跳过可能存在的额外fmt数据
            if (subchunk_size > 16) {
                fseek(fp, subchunk_size - 16, SEEK_CUR);
            }
            
            break;
        } else {
            // 跳过非fmt块
            fseek(fp, subchunk_size, SEEK_CUR);
        }
        
        // 防止无限循环
        if (feof(fp)) {
            fprintf(stderr, "Error: fmt chunk not found\n");
            return 0;
        }
    }
    
    // 检查音频格式
    if (audio_format != 1) {
        fprintf(stderr, "Error: Only PCM format is supported\n");
        return 0;
    }
    
    // 检查通道数
    if (num_channels != 1) {
        fprintf(stderr, "Error: Only mono audio is supported\n");
        return 0;
    }
    
    // 检查采样率
    if (sample_rate != 48000) {
        fprintf(stderr, "Warning: Sample rate is %d Hz, but 48kHz is recommended for best results.\n", 
                sample_rate);
    }
    
    // 检查位深度
    if (bits_per_sample != 16) {
        fprintf(stderr, "Error: Only 16-bit PCM is supported\n");
        return 0;
    }
    
    // 查找data块
    while (1) {
        subchunk_id = read_uint32(fp);
        subchunk_size = read_uint32(fp);
        
        if (subchunk_id == DATA_ID) {
            // 记录数据块位置和大小
            info->data_offset = ftell(fp);
            info->data_size = subchunk_size;
            break;
        } else {
            // 跳过非data块
            fseek(fp, subchunk_size, SEEK_CUR);
        }
        
        // 防止无限循环
        if (feof(fp)) {
            fprintf(stderr, "Error: data chunk not found\n");
            return 0;
        }
    }
    
    // 保存音频格式信息
    info->sample_rate = sample_rate;
    info->num_channels = num_channels;
    info->bits_per_sample = bits_per_sample;
    
    // 恢复文件位置
    fseek(fp, initial_pos, SEEK_SET);
    
    return 1;
}

// 写入WAV文件头
void write_wav_header(FILE *fp, WavInfo *info, unsigned int data_size) {
    // 定位到文件开始
    fseek(fp, 0, SEEK_SET);
    
    // RIFF头
    fwrite("RIFF", 1, 4, fp);
    write_uint32(fp, data_size + 36); // 文件总大小 - 8
    fwrite("WAVE", 1, 4, fp);
    
    // fmt块
    fwrite("fmt ", 1, 4, fp);
    write_uint32(fp, 16);                   // fmt块大小（不包含额外参数）
    write_uint16(fp, 1);                    // 音频格式（PCM = 1）
    write_uint16(fp, info->num_channels);   // 通道数
    write_uint32(fp, info->sample_rate);    // 采样率
    write_uint32(fp, info->sample_rate * info->num_channels * info->bits_per_sample / 8); // 每秒字节数
    write_uint16(fp, info->num_channels * info->bits_per_sample / 8); // 块对齐
    write_uint16(fp, info->bits_per_sample); // 每样本位数
    
    // data块
    fwrite("data", 1, 4, fp);
    write_uint32(fp, data_size);            // 音频数据大小（字节）
}

// 简单线性重采样（仅用于演示）
void simple_resample(short *input, int input_len, short *output, int output_len) {
    double step = (double)input_len / output_len;
    double pos = 0.0;
    
    for (int i = 0; i < output_len; i++) {
        int idx = (int)pos;
        double frac = pos - idx;
        
        if (idx >= input_len - 1)
            output[i] = input[input_len - 1];
        else
            output[i] = (short)((1.0 - frac) * input[idx] + frac * input[idx + 1]);
        
        pos += step;
    }
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input.wav> <output.wav>\n", argv[0]);
        return 1;
    }
    
    FILE *f_in, *f_out;
    WavInfo wav_info;
    DenoiseState *st;
    short *input_buffer = NULL, *output_buffer = NULL;
    float *input_frame = NULL, *output_frame = NULL;
    int samples_read, frames_processed = 0;
    unsigned int total_samples_written = 0;
    
    // 打开输入文件
    f_in = fopen(argv[1], "rb");
    if (!f_in) {
        fprintf(stderr, "Error opening input file: %s\n", argv[1]);
        return 1;
    }
    
    // 读取WAV头
    if (!read_wav_header(f_in, &wav_info)) {
        fclose(f_in);
        return 1;
    }
    
    // 打开输出文件
    f_out = fopen(argv[2], "wb");
    if (!f_out) {
        fprintf(stderr, "Error opening output file: %s\n", argv[2]);
        fclose(f_in);
        return 1;
    }
    
    // 写入临时WAV头（稍后更新）
    write_wav_header(f_out, &wav_info, 0);
    
    // 初始化RNNoise
    st = rnnoise_create();
    if (!st) {
        fprintf(stderr, "Error initializing RNNoise\n");
        fclose(f_in);
        fclose(f_out);
        return 1;
    }
    
    // 分配内存
    input_buffer = (short*)malloc(FRAME_SIZE * sizeof(short));
    output_buffer = (short*)malloc(FRAME_SIZE * sizeof(short));
    input_frame = (float*)malloc(FRAME_SIZE * sizeof(float));
    output_frame = (float*)malloc(FRAME_SIZE * sizeof(float));
    
    if (!input_buffer || !output_buffer || !input_frame || !output_frame) {
        fprintf(stderr, "Error allocating memory\n");
        if (input_buffer) free(input_buffer);
        if (output_buffer) free(output_buffer);
        if (input_frame) free(input_frame);
        if (output_frame) free(output_frame);
        rnnoise_destroy(st);
        fclose(f_in);
        fclose(f_out);
        return 1;
    }
    
    // 处理音频数据
    printf("Processing audio...\n");
    
    // 定位到数据块开始位置
    fseek(f_in, wav_info.data_offset, SEEK_SET);
    
    while ((samples_read = fread(input_buffer, sizeof(short), FRAME_SIZE, f_in)) > 0) {
        // 转换短整型到浮点
        for (int i = 0; i < samples_read; i++) {
            input_frame[i] = (float)input_buffer[i];
        }
        
        // 如果最后一帧不足，用0填充
        if (samples_read < FRAME_SIZE) {
            for (int i = samples_read; i < FRAME_SIZE; i++) {
                input_frame[i] = 0.0f;
            }
        }
        
        // 使用RNNoise处理
        rnnoise_process_frame(st, output_frame, input_frame);
        
        // 转换回短整型
        for (int i = 0; i < samples_read; i++) {
            // 限制在短整型范围内
            if (output_frame[i] > 32767.0f) output_frame[i] = 32767.0f;
            if (output_frame[i] < -32768.0f) output_frame[i] = -32768.0f;
            output_buffer[i] = (short)output_frame[i];
        }
        
        // 写入输出文件
        fwrite(output_buffer, sizeof(short), samples_read, f_out);
        total_samples_written += samples_read;
        
        frames_processed++;
        if (frames_processed % 100 == 0) {
            printf("Processed %d frames...\r", frames_processed);
            fflush(stdout);
        }
    }
    
    printf("\nProcessed %d frames. Done!\n", frames_processed);
    
    // 更新WAV头中的数据大小
    unsigned int data_size_bytes = total_samples_written * sizeof(short);
    write_wav_header(f_out, &wav_info, data_size_bytes);
    
    // 清理
    rnnoise_destroy(st);
    free(input_buffer);
    free(output_buffer);
    free(input_frame);
    free(output_frame);
    fclose(f_in);
    fclose(f_out);
    
    return 0;
} 