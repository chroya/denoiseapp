# Flutter RNNoise 语音降噪应用

一个基于 RNNoise 算法的实时语音降噪 Flutter 应用，支持文件处理和实时音频流处理。

## 🎯 主要功能

### 核心功能
- **实时语音降噪**: 基于 Mozilla RNNoise 算法的高质量语音降噪
- **文件音频处理**: 支持选择音频文件并进行降噪处理
- **流式播放**: 支持处理过程中的实时播放
- **多格式支持**: 支持 WAV 格式音频文件
- **暂停/恢复**: 完整的播放控制功能

### 技术特性
- **FFI 集成**: 原生 RNNoise C 库集成
- **模块化架构**: 清晰的服务层分离
- **流式处理**: 内存高效的音频块处理
- **状态管理**: 完整的播放状态管理
- **错误处理**: 友好的中文错误提示

## 🏗️ 架构设计

### 服务层架构
```
AudioManager (主控制器)
├── DenoiseService (RNNoise FFI 封装)
├── RecordingService (录音功能)
├── PlaybackService (播放功能)
├── FileProcessingService (文件处理)
└── WavUtils (WAV 工具类)
```

### 关键组件

#### AudioManager
- 统一的 API 入口
- 状态管理和协调
- 用户界面交互处理

#### DenoiseService
- RNNoise 算法封装
- 音频块降噪处理
- 内存管理

#### PlaybackService
- 基于 just_audio 的播放功能
- 支持文件播放和流式播放
- 音频会话管理

#### FileProcessingService
- 文件读取和处理
- WAV 格式解析
- 流式处理管道

## 📦 依赖库

### 核心依赖
```yaml
dependencies:
  flutter:
    sdk: flutter
  just_audio: ^0.9.40              # 音频播放
  audio_session: ^0.1.21           # 音频会话管理
  ffi: ^2.1.2                      # FFI 支持
  file_picker: ^8.1.2              # 文件选择
  record: ^5.1.2                   # 录音功能
  path_provider: ^2.1.4            # 路径管理
  permission_handler: ^11.3.1      # 权限管理
  path: ^1.9.0                     # 路径操作
```

## 🚀 安装和运行

### 环境要求
- Flutter SDK ≥ 3.0.0
- Android SDK ≥ 21
- iOS ≥ 11.0

### 安装步骤

1. **克隆项目**
```bash
git clone <repository-url>
cd flutter_rnn_denoise
```

2. **安装依赖**
```bash
flutter pub get
```

3. **配置权限**

Android (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
<application android:usesCleartextTraffic="true">
```

4. **运行应用**
```bash
flutter run
```

## 🎮 使用指南

### 基本操作

1. **选择音频文件**
   - 点击"选择文件"按钮
   - 选择 WAV 格式音频文件

2. **启用/禁用降噪**
   - 切换"降噪"开关
   - 绿色表示启用，灰色表示禁用

3. **播放控制**
   - 点击播放按钮开始播放
   - 再次点击暂停/恢复播放
   - 长按停止播放

### 功能说明

#### 普通播放模式
- 降噪开关关闭时
- 直接播放原始音频文件
- 适合预览原始音频

#### 降噪播放模式
- 降噪开关开启时
- 实时处理并播放降噪后的音频
- 显示"正在处理音频，请稍候..."状态

## 🛠️ 开发指南

### 项目结构
```
lib/
├── main.dart                    # 应用入口
├── src/
│   ├── audio_manager.dart       # 主控制器
│   ├── stream_demo_page.dart    # 主界面
│   ├── services/                # 服务层
│   │   ├── denoise_service.dart
│   │   ├── playback_service.dart
│   │   ├── recording_service.dart
│   │   └── file_processing_service.dart
│   └── utils/                   # 工具类
│       └── wav_utils.dart
```

### 关键配置

#### 音频参数
- 采样率: 48000 Hz
- 位深度: 16 bit
- 声道: 单声道 (自动转换)
- 块大小: 1 秒

#### 性能优化
- 流式处理避免内存溢出
- 异步处理防止 UI 阻塞
- 临时文件自动清理

## 🔧 已修复的问题

### v1.1.0 重大重构
1. **架构重构**: 从单一 1700+ 行类重构为模块化服务架构
2. **播放修复**: 修复播放按钮需要双击的问题
3. **音频修复**: 修复立体声到单声道转换导致的音频拉伸问题
4. **权限修复**: 添加 Android 音频权限支持
5. **网络修复**: 解决 just_audio 本地服务器连接问题
6. **状态同步**: 改进播放状态管理和同步
7. **错误处理**: 友好的中文错误提示信息
8. **文件管理**: 改进临时文件生命周期管理

### 性能改进
- 减少播放延迟从 300ms 到 50ms
- 优化内存使用
- 改进状态同步机制

## 🎵 音频格式支持

### 输入格式
- WAV (推荐): 完全支持
- 采样率: 16kHz-48kHz (自动处理采样率不匹配)
- 位深度: 16-bit (推荐)
- 声道: 单声道/立体声 (自动转换为单声道)

### 输出格式
- WAV 16-bit 单声道
- 采样率: 48kHz
- 实时流式输出

## 🐛 故障排除

### 常见问题

1. **"请先选择音频文件"**
   - 确保已选择有效的音频文件
   - 检查文件格式是否为 WAV

2. **"正在处理音频，请稍候..."**
   - 正常状态，等待处理完成
   - 避免重复点击播放按钮

3. **播放失败**
   - 检查文件是否存在
   - 确认音频格式兼容性
   - 重启应用重试

4. **权限问题**
   - 确保授予麦克风和存储权限
   - 在设置中手动开启权限

### 调试模式
启用详细日志输出:
```bash
flutter run --debug
```
查看控制台输出以获取详细错误信息。

## 📝 更新日志

### v1.1.0 (2024-06-07)
- 🔄 完全重构架构，采用模块化设计
- 🎵 修复音频拉伸问题 (立体声转单声道)
- 🎮 修复播放按钮双击问题
- 📱 改进 Android 权限处理
- 🌐 解决网络连接问题
- 🔧 优化状态管理和错误处理
- 🇨🇳 添加中文错误提示

### v1.0.0
- 🚀 基础 RNNoise 集成
- 📁 文件选择和播放功能
- 🎚️ 降噪开关功能

## 📄 许可证

本项目基于 MIT 许可证开源。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

### 开发环境设置
1. Fork 本项目
2. 创建功能分支: `git checkout -b feature/new-feature`
3. 提交更改: `git commit -am 'Add new feature'`
4. 推送到分支: `git push origin feature/new-feature`
5. 提交 Pull Request

## 📞 支持

如有问题，请提交 Issue 或联系开发团队。
