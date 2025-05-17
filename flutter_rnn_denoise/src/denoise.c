//
// Created by fryant on 2018/12/23.
//

#include <stdio.h>
#include <stdlib.h>
#include "rnnoise.h"

#define FRAME_SIZE 480

// C函数实现，供FFI调用
int rnnoise(const char* infile, const char* outfile) {
    FILE* f1 = fopen(infile, "rb");
    FILE* f2 = fopen(outfile, "wb");
    
    if (f1 == NULL || f2 == NULL) {
        return -1;
    }
    
    DenoiseState *st = rnnoise_create();
    short inbuf[480];
    float inbuf_f[480];
    float outbuf[480];
    short outbuf_s[480];
    
    while (1) {
        size_t n = fread(inbuf, sizeof(short), 480, f1);
        if (n != 480) {
            break;
        }
        
        // 将short转换为float
        for (int i=0; i<480; i++) {
            inbuf_f[i] = inbuf[i];
        }
        
        // 处理音频 - 参数顺序：st, out, in
        rnnoise_process_frame(st, outbuf, inbuf_f);
        
        // 将float转换为short
        for (int i=0; i<480; i++) {
            outbuf_s[i] = (short)outbuf[i];
        }
        
        // 写入输出文件
        fwrite(outbuf_s, sizeof(short), 480, f2);
    }
    
    rnnoise_destroy(st);
    fclose(f1);
    fclose(f2);
    return 0;
}