//
// Created by fryant on 2018/12/23.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rnnoise.h"

#ifdef __cplusplus
extern "C" {
#endif

#define FRAME_SIZE 480

// 全局状态管理
static DenoiseState* g_denoise_state = NULL;

// 初始化降噪状态
int rnnoise_init_state() {
    if (g_denoise_state != NULL) {
        rnnoise_destroy(g_denoise_state);
    }
    
    g_denoise_state = rnnoise_create(NULL);
    return g_denoise_state != NULL ? 0 : -1;
}

// 销毁降噪状态
void rnnoise_cleanup_state() {
    if (g_denoise_state != NULL) {
        rnnoise_destroy(g_denoise_state);
        g_denoise_state = NULL;
    }
}

// 处理多帧音频数据（流式处理核心函数）
float rnnoise_process_frames(float* output, const float* input, int num_frames) {
    if (output == NULL || input == NULL || num_frames <= 0) {
        return -1.0f;
    }
    
    if (g_denoise_state == NULL) {
        if (rnnoise_init_state() != 0) {
            return -1.0f;
        }
    }
    
    float total_vad_prob = 0.0f;
    
    for (int i = 0; i < num_frames; i++) {
        float vad_prob = rnnoise_process_frame(
            g_denoise_state,
            output + i * FRAME_SIZE,
            input + i * FRAME_SIZE
        );
        total_vad_prob += vad_prob;
    }
    
    return total_vad_prob / num_frames;
}

// C函数实现，供FFI调用
int rnnoise(const char* infile, const char* outfile) {
    if (infile == NULL || outfile == NULL) {
        return -1;
    }
    
    FILE* f1 = fopen(infile, "rb");
    FILE* f2 = fopen(outfile, "wb");
    
    if (f1 == NULL || f2 == NULL) {
        if (f1) fclose(f1);
        if (f2) fclose(f2);
        return -1;
    }
    
    DenoiseState *st = rnnoise_create(NULL);
    if (st == NULL) {
        fclose(f1);
        fclose(f2);
        return -1;
    }
    
    short inbuf[FRAME_SIZE];
    float inbuf_f[FRAME_SIZE];
    float outbuf[FRAME_SIZE];
    short outbuf_s[FRAME_SIZE];
    
    while (1) {
        size_t n = fread(inbuf, sizeof(short), FRAME_SIZE, f1);
        if (n != FRAME_SIZE) {
            break;
        }
        
        // 将short转换为float
        for (int i = 0; i < FRAME_SIZE; i++) {
            inbuf_f[i] = inbuf[i];
        }
        
        // 处理音频 - 参数顺序：st, out, in
        rnnoise_process_frame(st, outbuf, inbuf_f);
        
        // 将float转换为short
        for (int i = 0; i < FRAME_SIZE; i++) {
            outbuf_s[i] = (short)outbuf[i];
        }
        
        // 写入输出文件
        fwrite(outbuf_s, sizeof(short), FRAME_SIZE, f2);
    }
    
    rnnoise_destroy(st);
    fclose(f1);
    fclose(f2);
    return 0;
}

#ifdef __cplusplus
}
#endif