# RNN语音降噪工具

这是一个基于RNN的语音降噪工具，可在Linux和Mac上运行，用于处理WAV文件。该工具使用递归神经网络算法来降低音频中的背景噪声，同时保持语音清晰度。

## 最新更新

**2023-05-10: WAV文件处理修复与增强**
- 修复了WAV文件头处理问题，现在生成的文件可以正常播放
- 添加了音频格式转换脚本 `convert_audio.sh`
- 改进了批量处理脚本，添加了更详细的错误处理
- 详细修复信息请查看 `README_ISSUES.md`

## 功能特点

- 处理16位PCM单声道WAV文件
- 基于递归神经网络的高效降噪算法
- 命令行界面，易于集成到批处理流程中
- 支持Linux和macOS平台

## 编译方法

1. 确保已安装GCC和Make工具
2. 执行以下命令编译工具：

```bash
cd rnn_denoise_tool
make
```

编译成功后将在当前目录生成`rnn_denoise`可执行文件。

## 使用方法

### 使用脚本（推荐）

```bash
./denoise.sh input.wav output.wav
```

### 批量处理多个文件

```bash
./batch_process.sh input_directory output_directory
```

### 将其他音频格式转换为可处理的WAV

```bash
./convert_audio.sh input.mp3 output.wav
```

## 注意事项

- 本工具仅支持16位PCM单声道WAV文件
- 最佳效果需要48kHz采样率的音频文件
- 其他采样率的文件会产生警告，但仍可处理（质量可能受影响）
- 处理大文件时可能需要较长时间

## 工具说明

1. `denoise.sh` - 单文件处理脚本
2. `batch_process.sh` - 批量处理脚本
3. `convert_audio.sh` - 音频格式转换脚本（需要FFmpeg）
4. `rnn_denoise` - 核心降噪可执行文件

## 常见问题

详见 `README_ISSUES.md` 和 `USAGE_EXAMPLE.md`

## 许可证

本工具基于开源RNN降噪算法开发，遵循原算法的开源许可条款。

# RNN-based-Speech-noise-reduction-android-app
基于递归神经网络的语音降噪系统设计
=================

平台：Android
交互式界面 实时降噪

*   **关键代码说明**

原始代码文件中的各个函数有详细的注释，现将关键内容整理如下。

**onCreate**：初始化按钮；

**onClick****：**设置按钮触发事件

*   录制按钮：对麦克风的音频进行录制。触发startAudioRecord函数和stopAudioRecord函数，将结果保存为pcm文件
*   播放录制音频按钮：对麦克风录音进行播放。触发startAudioPlay函数和stopAudioPlay函数 读取原始pcm文件并进行播放
*   降噪处理按钮：对音频进行降噪处理。触发startAudioTran函数，输入为原始pcm文件，输出为降噪处理后的pcm文件
*   实时处理按钮：实时进行处理。触发为startRealTimeAudioTran函数。
*   开启/关闭实时降噪按钮：实时降噪效果的开关。修改Flag传给实时处理函数。

**startAudioRecord****：**

*   检测权限
*   开始RecordTask线程 调用AudioRecord；

**startAudioPlay****：**

*   开始PlayTask线程 调用AudioTrack；

**startAudioTran****：**

*   开启TranTask线程 调用rnnoise函数；

**startAudioTran****：**

*   开始RealTimeRecordTask线程 循环录取麦克风数据并将结果放入原始录音队列；
*   开始RealTimeTranTask线程 循环从原始录音队列读取数据进行处理并将处理结果放到播放队列；
*   开始RealTimePlayTask 循环从录音队列读取数据并调用AudioTrack播放；

降噪部分的rnnoise使用c语言实现。代码位于cpp文件夹下。封装为rnnoise降噪函数。输入为pcm文件，输出为处理后的pcm文件。

代码逻辑如下：

*   从原始pcm文件读取一帧音频；
*   对该帧音频计算特征。特征包括 22个Bark尺度，跨帧的前6个系数的一阶和二阶导数，基音周期（1 /基频），6频段的音高增益（发声强度）和一种特殊的非平稳值，可用于检测语音；
*   将特征传入rnn计算函数，根据预训练的网络执行forward和GRU单元。 输出为Bark尺度上的增益；
*   根据rnn输出计算出该帧输出的音频，写入结果中。

实时处理逻辑：

*   从录音线程获取音频buffer；
*   对buffer进行字节序变换（java默认大尾端存储short类型，而c默认小尾端） （重要）；
*   对buffer加上上一个buffer的最后一帧（480个short）（用于保证每一小段音频之间的连续性）（重要）；
*   将结果放入录音队列；
*   实时处理函数从录音队列读取一个buffer，交给rnnoise处理，将处理出的结果进行字节序变换，放入播放队列；
*   实时播放函数从播放队列中读取buffer进行播放。
*   **界面说明**

  **软件主界面**

软件主界面包括两个模块：

1.  录音降噪模块

此模块为实现录音音频文件降噪而设计。包括四个按钮，按照逻辑先后顺序介绍如下。

1.  点击"开始录制"即可启动麦克风收集语音，再次点击即可停止；
2.  随后点击"播放录制音频"即可开始播放未处理的原始录音；
3.  随后点击"降噪处理"即可完成降噪操作；
4.  最后点击"播放处理音频"即可播放降噪处理后的音频。
5.  实时降噪模块

此模块为实现实时音频降噪而设计。包括两个按钮，按照逻辑先后顺序介绍如下。

1.  佩戴蓝牙耳机，点击"实时返送"即可开始讲话，耳机中播放同步音频；
2.  讲话过程中，点击"开启实时降噪"即可开始降噪，耳机中播放同步降噪后音频，再次点击切换回原始音频，如此反复；
3.  点击"停止实时转换"即可结束模块。

