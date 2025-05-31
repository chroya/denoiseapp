 # Flutter RNNoise 流式处理指南

## 概述

本项目现在支持实时流式音频降噪处理，可以在录音的同时进行降噪处理，实现低延迟的实时音频处理。

## 新增功能

### 1. 多帧批处理
- 支持一次处理多个音频帧（默认4帧）
- 提高处理效率，减少FFI调用开销
- 可配置批处理大小

### 2. 流式处理
- 实时音频流处理
- 边录音边降噪
- 低延迟处理（约40ms）

### 3. 内存优化
- 对象池管理，减少内存分配
- 智能缓冲区管理
- 自动资源回收

### 4. VAD检测
- 实时语音活动检测
- 智能降噪控制
- 可视化VAD状态

## 核心组件

### AudioStreamProcessor
流式音频处理器，负责：
- 音频流的批处理
- 内存管理和对象池
- 统计信息收集

### AudioManagerStream
流式音频管理器，负责：
- 录音和播放控制
- 流处理生命周期管理
- 回调事件处理

### RNNoiseFFI (更新)
FFI接口，新增：
- `processFrames()` - 多帧批处理
- `initializeState()` - 状态初始化
- `cleanupState()` - 资源清理

## 使用方法

### 1. 初始化
```dart
final audioManager = AudioManagerStream();
await audioManager.initialize();
```

### 2. 设置回调
```dart
audioManager.onAudioProcessed = (result) {
  print('VAD概率: ${result.vadProbability}');
  // 处理降噪后的音频数据
};

audioManager.onStatusChanged = (status) {
  print('状态: $status');
};

audioManager.onError = (error) {
  print('错误: $error');
};
```

### 3. 开始实时处理
```dart
await audioManager.startStreamProcessing();
```

### 4. 停止处理
```dart
await audioManager.stopStreamProcessing();
```

### 5. 获取统计信息
```dart
final stats = audioManager.streamStats;
print('处理帧数: ${stats.totalFramesProcessed}');
print('平均VAD: ${stats.averageVadProbability}');
```

## 性能参数

### 音频参数
- 采样率: 48kHz
- 声道数: 1 (单声道)
- 位深度: 16位
- 帧大小: 480样本 (10ms)

### 处理参数
- 默认批处理大小: 4帧 (40ms)
- 处理延迟: ~40ms
- 内存使用: 优化的对象池管理

### 性能指标
- CPU使用率: 低
- 内存占用: 小
- 延迟: 低于50ms

## 配置选项

### 批处理大小
```dart
final processor = AudioStreamProcessor(framesPerBatch: 8); // 8帧批处理
```

### 缓冲区大小
```dart
// 在AudioStreamProcessor中配置
static const int MAX_BUFFER_SIZE = FRAME_SIZE * 16;
```

## 注意事项

### 1. 权限要求
- 麦克风权限
- 存储权限（用于文件保存）

### 2. 平台兼容性
- Android: 支持
- iOS: 支持
- 其他平台: 需要相应的动态库

### 3. 性能建议
- 使用较小的批处理大小以降低延迟
- 在性能较低的设备上可以增加批处理大小
- 监控内存使用情况

### 4. 错误处理
- 检查初始化状态
- 处理权限拒绝
- 监听错误回调

## 示例代码

完整的使用示例请参考 `StreamDemoPage`，包含：
- 实时处理控制
- 文件录音和处理
- 统计信息显示
- VAD可视化

## 故障排除

### 1. 初始化失败
- 检查权限是否授予
- 确认动态库是否正确加载
- 查看错误日志

### 2. 音频处理异常
- 确认音频格式正确（48kHz, 16位, 单声道）
- 检查内存是否充足
- 监控处理统计信息

### 3. 延迟过高
- 减少批处理大小
- 检查设备性能
- 优化缓冲区配置

## 技术细节

### FFI接口
C层新增函数：
```c
int rnnoise_init_state();
void rnnoise_cleanup_state();
float rnnoise_process_frames(float* output, const float* input, int num_frames);
```

### 内存管理
- 使用对象池减少内存分配
- 自动回收音频缓冲区
- 智能缓冲区大小控制

### 线程安全
- 主线程处理UI更新
- 后台线程处理音频数据
- 使用Stream进行线程间通信