import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path/path.dart' as path_helper;
import 'package:record/record.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'rnnoise_ffi.dart';
import 'audio_stream_processor.dart';
  import 'dart:math' as math;




/// 流式音频管理器类，支持实时降噪处理
class AudioManagerStream {
  // 单例
  static final AudioManagerStream _instance = AudioManagerStream._internal();
  factory AudioManagerStream() => _instance;
  AudioManagerStream._internal();

  // 录音器和播放器
  final _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  
  // RNNoise接口和流处理器
  final RNNoiseFFI _rnnoise = RNNoiseFFI();
  AudioStreamProcessor? _streamProcessor;
  
  // 状态
  bool _isInitialized = false;
  bool _isRecorderInitialized = false;
  bool _isRecording = false;
  bool _isStreamProcessing = false;
  
  // 文件路径
  late String _appDir;
  late String _recordingPath;
  late String _realtimeProcessedPath;
  late String _realtimeOriginalPath;
  
  // 添加文件处理相关路径和状态
  String? _selectedAudioFilePath;
  String? _selectedOriginalWavPath;
  String? _selectedProcessedWavPath;
  bool _isFileProcessing = false;
  
  // 新增：播放控制状态
  bool _isDenoisingEnabledForStream = false;
  bool _isDenoisingEnabledForFile = false;
  bool _isPlayingStream = false;
  bool _isPlayingFile = false;
  String? _currentPlayingFilePath;
  bool _isExpectedPlayerStop = false; // 标记播放器是否是预期中停止的

    // 分块流式处理相关
  ConcatenatingAudioSource? _concatenatingFileSource;
  List<String> _processedChunkFilePaths = [];
  bool _stopFileChunkProcessingLoop = false; // Flag to signal the chunk processing loop to stop
  bool _isChunkProcessingActive = false; // Specifically for the background chunk processing task
  static const int _chunkDurationSeconds = 1; // 改为1秒块，降低延迟
  
  // 双缓冲机制相关
  final Queue<Uint8List> _audioBufferQueue = Queue<Uint8List>(); // 内存音频缓冲队列
  final int _maxBufferQueueSize = 5; // 最大缓冲5秒音频
  bool _isBuffering = false;
  int _bufferPlaybackIndex = 0;
  
  // 优化播放相关
  bool _useMemoryStreamPlayback = true; // 使用优化的Data URI方案
  String? _currentTempFilePath; // 当前使用的临时文件路径
  
  // 流处理相关
  StreamSubscription<AudioProcessResult>? _streamProcessSubscription;
  StreamController<Uint8List>? _audioStreamController;
  StreamSubscription? _audioDataSubscription;
  Timer? _audioSaveTimer;
  
  // 音频数据缓冲
  final List<Float32List> _processedAudioBuffer = [];
  final List<Float32List> _originalAudioBuffer = [];
  final List<Float32List> _completeProcessedAudio = []; // 完整的处理后音频
  final List<Float32List> _completeOriginalAudio = []; // 完整的原始音频
  final int _maxBufferSize = 100; // 仅用于实时显示的缓冲区大小
  
  // 音频流处理
  final List<int> _rawAudioBuffer = [];
  static const int SAMPLE_RATE = 48000;
  static const int FRAME_SIZE = 480; // RNNoise帧大小
  
  // 真实音频数据读取
  int _audioFileReadPosition = 0;
  Timer? _audioReadTimer;
  
  // 回调函数
  Function(AudioProcessResult)? onAudioProcessed;
  Function(String)? onError;
  Function(String)? onStatusChanged;
  Function()? onStateChanged;
  
  // 获取状态
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  bool get isStreamProcessing => _isStreamProcessing;
  
  // 新增状态 getter
  bool get isDenoisingEnabledForStream => _isDenoisingEnabledForStream;
  bool get isDenoisingEnabledForFile => _isDenoisingEnabledForFile;
  bool get isPlayingStream => _isPlayingStream;
  bool get isPlayingFile => _isPlayingFile;
  
  // 添加文件处理状态getter
  bool get isFileProcessing => _isFileProcessing;
  String? get selectedAudioFilePath => _selectedAudioFilePath;
  
  /// 获取流处理统计信息
  AudioProcessorStats? get streamStats => _streamProcessor?.stats;
  
  /// 检查实时音频文件是否存在
  Future<bool> get hasRealtimeAudioFiles async {
    if (!_isInitialized) return false;
    
    final originalFile = File(_realtimeOriginalPath);
    final processedFile = File(_realtimeProcessedPath);
    
    return await originalFile.exists() && await processedFile.exists();
  }
  
  /// 检查原始音频文件是否存在
  Future<bool> get hasRealtimeOriginalFile async {
    if (!_isInitialized) return false;
    final file = File(_realtimeOriginalPath);
    return await file.exists();
  }
  
  /// 检查处理后音频文件是否存在
  Future<bool> get hasRealtimeProcessedFile async {
    if (!_isInitialized) return false;
    final file = File(_realtimeProcessedPath);
    return await file.exists();
  }
  
  /// 检查选择的音频文件是否已处理并可播放
  Future<bool> get hasSelectedAudioFiles async {
    if (!_isInitialized || _selectedOriginalWavPath == null) return false;
    final originalFile = File(_selectedOriginalWavPath!);
    return await originalFile.exists();
  }
  
  /// 初始化音频管理器
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // 先请求权限
      await _requestPermissions();
      
      // 初始化路径
      await _initializePaths();
      
      // 初始化音频会话
      await _initializeAudioSession();
      
      // 初始化录音器和播放器
      await _initializeRecorder();
      await _initializePlayers();
      
      // 初始化RNNoise
      await _initializeRNNoise();
      
      // 初始化流处理器
      await _initializeStreamProcessor();
      
      _isInitialized = true;
      onStatusChanged?.call('音频管理器初始化完成');
    } catch (e) {
      onError?.call('初始化失败: $e');
      rethrow;
    }
  }

  /// 初始化RNNoise
  Future<void> _initializeRNNoise() async {
    try {
      if (!_rnnoise.isLibraryLoaded) {
        throw Exception('RNNoise库未加载');
      }
      
      final success = _rnnoise.initializeState();
      if (!success) {
        throw Exception('RNNoise状态初始化失败');
      }
      
      print('RNNoise初始化成功');
    } catch (e) {
      throw Exception('RNNoise初始化失败: $e');
    }
  }
  
  /// 手动测试RNNoise FFI调用（可选调用）
  Future<void> testRNNoiseFFI() async {
    try {
      print('=== RNNoise FFI测试开始 ===');
      
      // 测试1: 纯噪声输入
      final noiseAudio = Float32List(FRAME_SIZE);
      for (int i = 0; i < FRAME_SIZE; i++) {
        noiseAudio[i] = (math.Random().nextDouble() - 0.5) * 0.5; // 随机噪声
      }
      
      final noiseResult = _rnnoise.processFrames(noiseAudio, 1);
      final noiseInputRMS = _calculateRMS(noiseAudio);
      final noiseOutputRMS = _calculateRMS(noiseResult.processedAudio);
      
      print('噪声测试:');
      print('  输入RMS: ${noiseInputRMS.toStringAsFixed(4)}');
      print('  输出RMS: ${noiseOutputRMS.toStringAsFixed(4)}');
      print('  VAD概率: ${noiseResult.vadProbability.toStringAsFixed(3)}');
      print('  抑制比: ${(noiseOutputRMS/noiseInputRMS).toStringAsFixed(3)}');
      
      // 测试2: 语音信号输入
      final speechAudio = Float32List(FRAME_SIZE);
      for (int i = 0; i < FRAME_SIZE; i++) {
        final t = i / SAMPLE_RATE;
        speechAudio[i] = math.sin(2 * math.pi * 440 * t) * 0.3; // 440Hz正弦波
      }
      
      final speechResult = _rnnoise.processFrames(speechAudio, 1);
      final speechInputRMS = _calculateRMS(speechAudio);
      final speechOutputRMS = _calculateRMS(speechResult.processedAudio);
      
      print('语音测试:');
      print('  输入RMS: ${speechInputRMS.toStringAsFixed(4)}');
      print('  输出RMS: ${speechOutputRMS.toStringAsFixed(4)}');
      print('  VAD概率: ${speechResult.vadProbability.toStringAsFixed(3)}');
      print('  保留比: ${(speechOutputRMS/speechInputRMS).toStringAsFixed(3)}');
      
      // 测试3: 混合信号（语音+噪声）
      final mixedAudio = Float32List(FRAME_SIZE);
      for (int i = 0; i < FRAME_SIZE; i++) {
        final t = i / SAMPLE_RATE;
        final speech = math.sin(2 * math.pi * 440 * t) * 0.3;
        final noise = (math.Random().nextDouble() - 0.5) * 0.2;
        mixedAudio[i] = speech + noise;
      }
      
      final mixedResult = _rnnoise.processFrames(mixedAudio, 1);
      final mixedInputRMS = _calculateRMS(mixedAudio);
      final mixedOutputRMS = _calculateRMS(mixedResult.processedAudio);
      
      print('混合信号测试:');
      print('  输入RMS: ${mixedInputRMS.toStringAsFixed(4)}');
      print('  输出RMS: ${mixedOutputRMS.toStringAsFixed(4)}');
      print('  VAD概率: ${mixedResult.vadProbability.toStringAsFixed(3)}');
      print('  处理比: ${(mixedOutputRMS/mixedInputRMS).toStringAsFixed(3)}');
      
      // 判断RNNoise是否工作正常
      bool isWorking = false;
      if (noiseResult.vadProbability < 0.5 && (noiseOutputRMS < noiseInputRMS * 0.8)) {
        print('✅ 噪声正确被抑制');
        isWorking = true;
      } else {
        print('❌ 噪声抑制效果不佳');
      }
      
      if (speechResult.vadProbability > 0.3 && (speechOutputRMS > speechInputRMS * 0.7)) {
        print('✅ 语音信号正确保留');
        isWorking = true;
      } else {
        print('❌ 语音信号保留不佳');
      }
      
      if (isWorking) {
        print('✅ RNNoise FFI基本功能正常');
      } else {
        print('⚠️  RNNoise FFI可能存在问题，建议检查C层实现');
      }
      
      print('=== RNNoise FFI测试结束 ===');
      
    } catch (e) {
      print('FFI测试失败: $e');
      throw e;
    }
  }
  
  /// 生成带噪声的测试音频（用于验证降噪效果）
  Future<void> generateNoisyTestAudio() async {
    if (!_isInitialized) {
      onError?.call('音频管理器未初始化');
      return;
    }
    
    try {
      print('开始生成带噪声的测试音频...');
      
      // 清空缓冲区
      _completeProcessedAudio.clear();
      _completeOriginalAudio.clear();
      
      // 生成5秒的测试音频（48kHz = 240000样本）
      const totalSamples = SAMPLE_RATE * 5;
      const numFrames = totalSamples ~/ FRAME_SIZE;
      
      for (int frameIndex = 0; frameIndex < numFrames; frameIndex++) {
        // 生成一帧音频：语音信号 + 噪声
        final inputFrame = Float32List(FRAME_SIZE);
        
        for (int i = 0; i < FRAME_SIZE; i++) {
          final t = (frameIndex * FRAME_SIZE + i) / SAMPLE_RATE;
          
          // 语音信号：多频率正弦波组合（模拟语音）
          final speech = math.sin(2 * math.pi * 440 * t) * 0.3 +  // 基频
                        math.sin(2 * math.pi * 880 * t) * 0.2 +  // 倍频
                        math.sin(2 * math.pi * 1320 * t) * 0.1; // 高频
          
          // 背景噪声：白噪声
          final noise = (math.Random().nextDouble() - 0.5) * 0.4;
          
          // 组合信号
          inputFrame[i] = speech + noise;
        }
        
        // 调用FFI处理
        final result = _rnnoise.processFrames(inputFrame, 1);
        
        // 保存到缓冲区
        _completeOriginalAudio.add(Float32List.fromList(inputFrame));
        _completeProcessedAudio.add(Float32List.fromList(result.processedAudio));
        
        // 显示进度
        if (frameIndex % 100 == 0) {
          final progress = (frameIndex / numFrames * 100).toInt();
          print('生成进度: $progress% (${frameIndex}/${numFrames}帧)');
        }
      }
      
      // 保存测试音频文件
      await _saveFinalAudioFiles();
      
      // 分析降噪效果
      _analyzeAudioDifference();
      
      onStatusChanged?.call('带噪声测试音频生成完成');
      print('测试音频生成完成，可以播放对比降噪效果');
      
    } catch (e) {
      onError?.call('生成测试音频失败: $e');
      print('生成测试音频失败: $e');
    }
  }
  
  /// 初始化流处理器
  Future<void> _initializeStreamProcessor() async {
    try {
      _streamProcessor = AudioStreamProcessor(framesPerBatch: 4);
      final success = await _streamProcessor!.initialize();
      if (!success) {
        _streamProcessor = null;
        throw Exception('流处理器初始化失败');
      }
    } catch (e) {
      _streamProcessor = null;
      throw Exception('流处理器初始化失败: $e');
    }
  }
  
  /// 请求所需权限
  Future<void> _requestPermissions() async {
    final microphoneStatus = await Permission.microphone.request();
    if (microphoneStatus != PermissionStatus.granted) {
      throw Exception('权限 ${Permission.microphone.toString()} 未授予');
    }
    
    print('权限请求完成 - 麦克风: $microphoneStatus');
  }
  
  /// 初始化文件路径
  Future<void> _initializePaths() async {
    final directory = await getApplicationDocumentsDirectory();
    _appDir = directory.path;
    _recordingPath = path_helper.join(_appDir, 'recording.wav');
    _realtimeProcessedPath = path_helper.join(_appDir, 'realtime_processed.wav');
    _realtimeOriginalPath = path_helper.join(_appDir, 'realtime_original.wav');
  }
  
  /// 初始化音频会话
  Future<void> _initializeAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  }
  
  /// 初始化录音器
  Future<void> _initializeRecorder() async {
    if (await _recorder.hasPermission()) {
      _isRecorderInitialized = true;
    } else {
      throw Exception('录音权限未授予');
    }
  }
  
  /// 初始化播放器
  Future<void> _initializePlayers() async {
    // 初始化统一播放器
    await _player.setVolume(1.0);
    
      // 设置播放状态监听器
  _player.playerStateStream.listen((state) {
    if (state.processingState == ProcessingState.completed) {
      final bool wasPlayingStream = _isPlayingStream;
      final bool wasPlayingFile = _isPlayingFile; // This line should already exist

      _isPlayingStream = false;
      
      // 检查是否是渐进式播放模式，如果是则不要设置 _isPlayingFile = false
      if (wasPlayingFile && !_useMemoryStreamPlayback) {
        _isPlayingFile = false; // 只有非渐进式播放才设置为false
      } else if (wasPlayingFile && _useMemoryStreamPlayback) {
        // 渐进式播放模式：检查是否真的完成了所有内容
        if (!_isChunkProcessingActive && _audioBufferQueue.isEmpty) {
          _isPlayingFile = false;
          _isFileProcessing = false;
          print("Progressive playback truly completed - all chunks processed");
        } else {
          print("Progressive playback: ignoring intermediate completion event");
          return; // 忽略中间的完成事件
        }
      }

      if (wasPlayingFile && !_isPlayingFile) { // 只有真正完成时才执行
        _isFileProcessing = false;
        print("File playback completed, _isFileProcessing set to false.");
      }
      _currentPlayingFilePath = null; // This line should already exist
      
      if (wasPlayingStream) {
        onStatusChanged?.call('实时音频播放完成');
        print('实时音频播放完成');
      }
      if (wasPlayingFile && !_isPlayingFile) {
        onStatusChanged?.call('文件音频播放完成');
        print('文件音频播放完成');
      }
      onStateChanged?.call(); // This line should already exist
    } else if (state.processingState == ProcessingState.ready && !state.playing) {
      // Handle pause state if needed, or rely on explicit pause calls
    }
  });
    _player.playingStream.listen((playing) {
        // This stream updates when player.play() or player.pause() is called.
        // We manage _isPlayingStream and _isPlayingFile in their respective toggle methods.
        // However, if an external event stops playback (e.g. another app takes audio focus),
        // this `playing` status might become false.
        if (_isExpectedPlayerStop) { // If we expected the player to stop (e.g., user pressed pause/stop)
            _isExpectedPlayerStop = false; // Reset the flag
            print("Player stopped as expected. Ignoring playingStream update for this event.");
            return; // Do not proceed with the unexpected stop logic
        }

        if (!playing && (_isPlayingStream || _isPlayingFile)) {
            // If player stops unexpectedly
            print("Player stopped unexpectedly. Updating state.");
            _isPlayingStream = false;
            _isPlayingFile = false;
            _isFileProcessing = false; // Also reset processing state if it was active
            _currentPlayingFilePath = null;
            onStateChanged?.call();
        }
    });

    // _isPlayerInitialized = true; // 不再需要单独的标志
    print('统一播放器 just_audio 初始化完成');
  }
  
  /// 开始实时流处理
  Future<void> startStreamProcessing() async {
    if (!_isInitialized || !_isRecorderInitialized || _isStreamProcessing) {
      onError?.call('音频管理器未初始化或正在进行流处理');
      return;
    }
    
    if (_streamProcessor == null) {
      onError?.call('流处理器未初始化');
      return;
    }
    
    try {
      // 清空缓冲区
      _rawAudioBuffer.clear();
      _processedAudioBuffer.clear();
      _originalAudioBuffer.clear();
      _completeProcessedAudio.clear();
      _completeOriginalAudio.clear();
      
      // 创建音频流控制器
      _audioStreamController = StreamController<Uint8List>.broadcast();
      
      // 监听音频数据流
      _setupAudioStreamProcessing();
      
      // 开始录音并获取音频流
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,  // 使用WAV格式确保兼容性
          sampleRate: SAMPLE_RATE,
          numChannels: 1,
          bitRate: 16,
        ),
        path: _recordingPath,
      );
      
      // 启动音频流读取
      await _startAudioStreamReading();
      
      _isStreamProcessing = true;
      _isRecording = true;
      
      // 启动音频保存定时器
      _startAudioSaveTimer();
      
      onStatusChanged?.call('开始实时流处理');
      onStateChanged?.call();
      
    } catch (e) {
      onError?.call('启动实时流处理失败: $e');
      throw Exception('启动实时流处理失败: $e');
    }
  }

  /// 设置音频流处理
  void _setupAudioStreamProcessing() {
    _audioDataSubscription = _audioStreamController!.stream.listen(
      (audioData) {
        _processAudioStreamData(audioData);
      },
      onError: (error) {
        onError?.call('音频流处理错误: $error');
      },
    );
  }

  /// 启动音频流读取（从录音文件读取真实音频数据）
  Future<void> _startAudioStreamReading() async {
    // 重置读取位置
    _audioFileReadPosition = 44; // 跳过WAV文件头
    
    // 每100ms读取一次录音文件的新数据
    _audioReadTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isStreamProcessing) {
        timer.cancel();
        return;
      }
      
      // 从录音文件读取新的音频数据
      await _readAudioDataFromFile();
    });
  }

  /// 从录音文件读取音频数据
  Future<void> _readAudioDataFromFile() async {
    try {
      final file = File(_recordingPath);
      if (!await file.exists()) {
        return;
      }
      
      final fileBytes = await file.readAsBytes();
      
      // WAV文件最小应该有44字节的文件头
      if (fileBytes.length <= 44) {
        return;
      }
      
      // 首次读取时，检查WAV文件头并找到数据开始位置
      if (_audioFileReadPosition == 44) {
        // 简单验证是否为WAV文件
        final riffHeader = String.fromCharCodes(fileBytes.sublist(0, 4));
        final waveHeader = String.fromCharCodes(fileBytes.sublist(8, 12));
        
        if (riffHeader != 'RIFF' || waveHeader != 'WAVE') {
          print('警告：文件可能不是有效的WAV格式');
        }
        
        // 查找数据块开始位置
        int dataStart = 44; // 标准WAV文件头大小
        
        // 更精确地查找"data"块
        for (int i = 12; i < fileBytes.length - 8; i += 4) {
          final chunkId = String.fromCharCodes(fileBytes.sublist(i, i + 4));
          if (chunkId == 'data') {
            dataStart = i + 8; // 跳过"data"标识和大小字段
            break;
          }
        }
        
        _audioFileReadPosition = dataStart;
        print('WAV文件数据开始位置: $dataStart');
      }
      
      // 如果文件太小（没有新数据），跳过
      if (fileBytes.length <= _audioFileReadPosition) {
        return;
      }
      
      // 计算要读取的字节数（每次读取约100ms的音频数据）
      const samplesToRead = SAMPLE_RATE ~/ 10; // 100ms的样本数
      const bytesToRead = samplesToRead * 2; // 16位PCM，每样本2字节
      final endPos = math.min(_audioFileReadPosition + bytesToRead, fileBytes.length);
      
      if (endPos <= _audioFileReadPosition) {
        return;
      }
      
      // 确保读取的字节数是偶数（16位样本需要2字节对齐）
      final actualBytesToRead = ((endPos - _audioFileReadPosition) ~/ 2) * 2;
      final actualEndPos = _audioFileReadPosition + actualBytesToRead;
      
      if (actualBytesToRead < 2) {
        return;
      }
      
      // 读取音频数据
      final audioBytes = fileBytes.sublist(_audioFileReadPosition, actualEndPos);
      _audioFileReadPosition = actualEndPos;
      
      // 发送音频数据到处理流
      if (audioBytes.isNotEmpty) {
        _audioStreamController?.add(Uint8List.fromList(audioBytes));
      }
      
    } catch (e) {
      print('读取音频文件数据失败: $e');
    }
  }

  /// 生成音频帧数据（备用方法，当无法读取真实数据时使用）
  Uint8List _generateAudioFrame() {
    // 生成480个样本的音频数据（16位PCM）
    final samples = Int16List(FRAME_SIZE);
    
    for (int i = 0; i < FRAME_SIZE; i++) {
      // 生成包含噪声的测试信号
      final t = DateTime.now().millisecondsSinceEpoch / 1000.0 + i / SAMPLE_RATE;
      final signal = math.sin(2 * math.pi * 440 * t) * 0.5; // 440Hz正弦波
      final noise = (math.Random().nextDouble() - 0.5) * 0.1; // 噪声
      final sample = ((signal + noise) * 16384).clamp(-32768, 32767);
      samples[i] = sample.round();
    }
    
    return samples.buffer.asUint8List();
  }

  /// 处理音频流数据
  void _processAudioStreamData(Uint8List audioData) {
    try {
      // 将字节数据转换为16位PCM样本
      final samples = Int16List.view(audioData.buffer);
      
      // 添加到原始音频缓冲区
      _rawAudioBuffer.addAll(samples);
      
      // 当有足够数据时处理一帧
      while (_rawAudioBuffer.length >= FRAME_SIZE) {
        // 提取一帧数据
        final frameData = _rawAudioBuffer.take(FRAME_SIZE).toList();
        _rawAudioBuffer.removeRange(0, FRAME_SIZE);
        
        // 转换为Float32List
        final inputFrame = Float32List(FRAME_SIZE);
        for (int i = 0; i < FRAME_SIZE; i++) {
          inputFrame[i] = frameData[i] / 32768.0; // 归一化到-1~1
        }
        
        // 调用FFI进行降噪处理
        final result = _rnnoise.processFrames(inputFrame, 1);
        
        // 添加调试信息，验证FFI是否真正在工作
        final inputRMS = _calculateRMS(inputFrame);
        final outputRMS = _calculateRMS(result.processedAudio);
        final vadProb = result.vadProbability;
        
        // 每处理100帧打印一次详细信息
        if (_completeProcessedAudio.length % 100 == 0) {
          print('FFI处理验证 - 帧数: ${_completeProcessedAudio.length}, '
                '输入RMS: ${inputRMS.toStringAsFixed(4)}, '
                '输出RMS: ${outputRMS.toStringAsFixed(4)}, '
                'VAD概率: ${vadProb.toStringAsFixed(3)}, '
                '音频变化: ${(outputRMS/inputRMS).toStringAsFixed(3)}');
        }
        
        // 保存到实时缓冲区（用于实时显示）
        _originalAudioBuffer.add(inputFrame);
        _processedAudioBuffer.add(result.processedAudio);
        
        // 同时保存到完整音频缓冲区（用于最终播放）
        _completeOriginalAudio.add(Float32List.fromList(inputFrame));
        _completeProcessedAudio.add(Float32List.fromList(result.processedAudio));
        
        // 限制实时缓冲区大小（只影响实时显示，不影响完整音频）
        if (_originalAudioBuffer.length > _maxBufferSize) {
          _originalAudioBuffer.removeAt(0);
        }
        if (_processedAudioBuffer.length > _maxBufferSize) {
          _processedAudioBuffer.removeAt(0);
        }
        
        // 通知处理结果
        final processResult = AudioProcessResult(
          processedAudio: result.processedAudio,
          vadProbability: result.vadProbability,
          framesProcessed: _completeProcessedAudio.length, // 使用完整音频的帧数
          timestamp: DateTime.now(),
        );
        
        onAudioProcessed?.call(processResult);
      }
      
    } catch (e) {
      onError?.call('音频流处理失败: $e');
    }
  }
  
  /// 停止实时流处理
  Future<void> stopStreamProcessing() async {
    if (!_isStreamProcessing) return;
    
    try {
      // 停止录音
      await _recorder.stop();
      
      // 停止音频读取定时器
      _audioReadTimer?.cancel();
      _audioReadTimer = null;
      
      // 取消音频流订阅
      await _audioDataSubscription?.cancel();
      _audioDataSubscription = null;
      
      // 关闭音频流控制器
      await _audioStreamController?.close();
      _audioStreamController = null;
      
      // 停止定时器
      _audioSaveTimer?.cancel();
      _audioSaveTimer = null;
      
      // 如果正在播放实时流，则停止播放
      if (_isPlayingStream) {
        _isExpectedPlayerStop = true;
        await _player.stop();
        _isPlayingStream = false;
        _currentPlayingFilePath = null;
      }

      _isStreamProcessing = false;
      _isRecording = false;
      
      // 保存最终的音频文件
      await _saveFinalAudioFiles();
      
      // 分析音频处理效果
      _analyzeAudioDifference();
      
      onStatusChanged?.call('停止实时流处理');
      onStateChanged?.call();
      
    } catch (e) {
      onError?.call('停止实时流处理失败: $e');
      throw Exception('停止实时流处理失败: $e');
    }
  }

  /// 保存最终音频文件
  Future<void> _saveFinalAudioFiles() async {
    if (_completeProcessedAudio.isEmpty || _completeOriginalAudio.isEmpty) {
      return;
    }
    
    try {
      // 合并所有音频帧（使用完整的音频数据）
      final processedAudio = _mergeAudioFrames(_completeProcessedAudio);
      final originalAudio = _mergeAudioFrames(_completeOriginalAudio);
      
      // 保存为WAV文件
      await _saveAudioAsWav(processedAudio, _realtimeProcessedPath);
      await _saveAudioAsWav(originalAudio, _realtimeOriginalPath);
      
      print('音频文件保存完成 - 原始音频: ${originalAudio.length}样本, 处理后音频: ${processedAudio.length}样本');
      
    } catch (e) {
      print('保存最终音频文件失败: $e');
    }
  }

  /// 开始录音（不处理）
  Future<void> startRecording() async {
    if (!_isInitialized || !_isRecorderInitialized || _isRecording) {
      onError?.call('录音器未初始化或正在录音');
      return;
    }
    
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,  // 使用WAV格式确保兼容性
          sampleRate: SAMPLE_RATE,
          numChannels: 1,
          bitRate: 16,
        ),
        path: _recordingPath,
      );
      
      _isRecording = true;
      onStatusChanged?.call('开始录音');
      onStateChanged?.call();
      
    } catch (e) {
      onError?.call('开始录音失败: $e');
      throw Exception('开始录音失败: $e');
    }
  }
  
  /// 停止录音
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    
    try {
      await _recorder.stop();
      _isRecording = false;
      onStatusChanged?.call('停止录音');
      onStateChanged?.call();
      
    } catch (e) {
      onError?.call('停止录音失败: $e');
      throw Exception('停止录音失败: $e');
    }
  }

  /// 启动音频保存定时器
  void _startAudioSaveTimer() {
    _audioSaveTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isStreamProcessing) {
        timer.cancel();
        return;
      }
      
      _saveRecentAudioToFiles();
    });
  }
  
  /// 保存最近的音频数据到文件
  Future<void> _saveRecentAudioToFiles() async {
    if (_completeProcessedAudio.isEmpty || _completeOriginalAudio.isEmpty) {
      return;
    }
    
    try {
      // 使用完整的音频数据
      final processedAudio = _mergeAudioFrames(_completeProcessedAudio);
      final originalAudio = _mergeAudioFrames(_completeOriginalAudio);
      
      // 保存为WAV文件（这样可以在录音过程中随时播放完整的音频）
      await _saveAudioAsWav(processedAudio, _realtimeProcessedPath);
      await _saveAudioAsWav(originalAudio, _realtimeOriginalPath);
      
      print('定期保存完成 - 当前音频长度: ${originalAudio.length}样本 (${(originalAudio.length / SAMPLE_RATE).toStringAsFixed(1)}秒)');
      
    } catch (e) {
      print('保存音频文件失败: $e');
    }
  }
  
  /// 合并音频帧
  Float32List _mergeAudioFrames(List<Float32List> frames) {
    if (frames.isEmpty) return Float32List(0);
    
    final totalLength = frames.fold<int>(0, (sum, frame) => sum + frame.length);
    final merged = Float32List(totalLength);
    
    int offset = 0;
    for (final frame in frames) {
      merged.setRange(offset, offset + frame.length, frame);
      offset += frame.length;
    }
    
    return merged;
  }
  
  /// 保存音频数据为WAV文件
  Future<void> _saveAudioAsWav(Float32List audioData, String filePath) async {
    try {
      print('开始保存WAV文件: $filePath');
      print('音频数据长度: ${audioData.length}样本');
      
      final file = File(filePath);
      
      // 转换float32到int16
      final int16Data = Int16List(audioData.length);
      for (int i = 0; i < audioData.length; i++) {
        int16Data[i] = (audioData[i] * 32767).clamp(-32768, 32767).round();
      }
      
      // 创建WAV文件头
      final sampleRate = SAMPLE_RATE;
      final numChannels = 1;
      final bitsPerSample = 16;
      final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
      final blockAlign = numChannels * bitsPerSample ~/ 8;
      final dataSize = int16Data.length * 2;
      final fileSize = 36 + dataSize;
      
      print('WAV文件参数:');
      print('  采样率: ${sampleRate}Hz');
      print('  声道数: $numChannels');
      print('  位深度: ${bitsPerSample}bit');
      print('  数据大小: ${dataSize}字节');
      print('  文件大小: ${fileSize}字节');
      
      final header = ByteData(44);
      header.setUint32(0, 0x52494646, Endian.big); // "RIFF"
      header.setUint32(4, fileSize, Endian.little);
      header.setUint32(8, 0x57415645, Endian.big); // "WAVE"
      header.setUint32(12, 0x666d7420, Endian.big); // "fmt "
      header.setUint32(16, 16, Endian.little); // fmt chunk size
      header.setUint16(20, 1, Endian.little); // PCM format
      header.setUint16(22, numChannels, Endian.little);
      header.setUint32(24, sampleRate, Endian.little);
      header.setUint32(28, byteRate, Endian.little);
      header.setUint16(32, blockAlign, Endian.little);
      header.setUint16(34, bitsPerSample, Endian.little);
      header.setUint32(36, 0x64617461, Endian.big); // "data"
      header.setUint32(40, dataSize, Endian.little);
      
      // 写入文件
      final bytes = <int>[];
      bytes.addAll(header.buffer.asUint8List());
      bytes.addAll(int16Data.buffer.asUint8List());
      
      await file.writeAsBytes(bytes);
      
      // 验证文件是否成功保存
      final savedFile = File(filePath);
      if (await savedFile.exists()) {
        final savedSize = await savedFile.length();
        print('WAV文件保存成功: ${savedSize}字节');
        
        if (savedSize != bytes.length) {
          print('警告：保存的文件大小与预期不符');
        }
      } else {
        print('错误：WAV文件保存失败，文件不存在');
      }
      
    } catch (e) {
      print('保存WAV文件失败: $e');
      throw Exception('保存WAV文件失败: $e');
    }
  }
  
  /// 播放实时原始音频
  Future<void> playRealtimeOriginal() async {
    // await _playRealtimeAudio(_realtimeOriginalPath, _originalPlayer, '播放原始音频');
    // 替换为 toggleStreamPlayback
    print("playRealtimeOriginal 废弃, 请使用 toggleStreamPlayback");
  }
  
  /// 播放实时降噪音频
  Future<void> playRealtimeProcessed() async {
    // await _playRealtimeAudio(_realtimeProcessedPath, _processedPlayer, '播放降噪音频');
    // 替换为 toggleStreamPlayback
    print("playRealtimeProcessed 废弃, 请使用 toggleStreamPlayback");
  }
  
  /// 播放实时音频的通用方法
  Future<void> _playAudio(String audioPath, String messagePrefix) async {
    print('准备播放音频: $audioPath');

    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      print('音频文件不存在: $audioPath');
      onError?.call('音频文件不存在，请等待或重新生成');
      return;
    }

    final fileSize = await audioFile.length();
    print('音频文件大小: ${fileSize}字节');
    if (fileSize < 1000) { // 小于1KB的文件可能有问题
      print('音频文件太小，可能数据不完整');
      onError?.call('音频文件数据不完整');
      return;
    }

    try {
      _currentPlayingFilePath = audioPath;
      await _player.setAudioSource(AudioSource.uri(Uri.file(audioPath)));
      await _player.play();
      // _isPlaying will be set by specific toggle methods
      onStatusChanged?.call('$messagePrefix 开始播放');
      Fluttertoast.showToast(msg: '$messagePrefix 开始播放');
      print('播放开始成功: $messagePrefix');
    } catch (e) {
      print('播放失败: $e');
      onError?.call('播放失败: $e');
      _currentPlayingFilePath = null;
      // Reset specific playing flags if error occurs
      if (_isPlayingStream && audioPath.contains("realtime")) _isPlayingStream = false;
      if (_isPlayingFile && audioPath.contains("selected")) _isPlayingFile = false;

      onStateChanged?.call();
    }
  }
  
  /// 计算音频RMS值（用于验证处理效果）
  double _calculateRMS(Float32List audioData) {
    if (audioData.isEmpty) return 0.0;
    
    double sum = 0.0;
    for (int i = 0; i < audioData.length; i++) {
      sum += audioData[i] * audioData[i];
    }
    return math.sqrt(sum / audioData.length);
  }
  
  /// 比较原始音频和处理后音频的差异
  void _analyzeAudioDifference() {
    if (_completeOriginalAudio.isEmpty || _completeProcessedAudio.isEmpty) {
      return;
    }
    
    final originalMerged = _mergeAudioFrames(_completeOriginalAudio);
    final processedMerged = _mergeAudioFrames(_completeProcessedAudio);
    
    final originalRMS = _calculateRMS(originalMerged);
    final processedRMS = _calculateRMS(processedMerged);
    
    // 计算平均差异
    double totalDiff = 0.0;
    final minLength = math.min(originalMerged.length, processedMerged.length);
    
    for (int i = 0; i < minLength; i++) {
      totalDiff += (originalMerged[i] - processedMerged[i]).abs();
    }
    
    final avgDiff = totalDiff / minLength;
    final rmsRatio = processedRMS / originalRMS;
    
    print('=== 音频处理分析报告 ===');
    print('原始音频RMS: ${originalRMS.toStringAsFixed(6)}');
    print('处理后音频RMS: ${processedRMS.toStringAsFixed(6)}');
    print('RMS比值: ${rmsRatio.toStringAsFixed(3)} (1.0表示无变化)');
    print('平均样本差异: ${avgDiff.toStringAsFixed(6)}');
    print('处理样本数: ${minLength}');
    
    if (avgDiff < 0.001) {
      print('⚠️  警告：音频差异很小，可能FFI处理未生效');
    } else {
      print('✅ 音频已通过FFI处理，存在明显差异');
    }
  }
  
  /// 处理选择的音频文件 - 重构为仅准备路径
  Future<void> selectAudioFileAndPreparePaths(String filePath) async {
    if (!_isInitialized) {
      onError?.call('音频管理器未初始化');
      return;
    }
    // if (_isFileProcessing) { // 这个状态现在用于表示 *降噪处理中*，而不是文件选择中
    //   onError?.call('正在处理其他音频文件，请等待');
    //   return;
    // }

    onStatusChanged?.call('选择音频文件: ${path_helper.basename(filePath)}');
    
    _selectedAudioFilePath = filePath;
    final fileName = path_helper.basenameWithoutExtension(filePath);
    final fileExt = path_helper.extension(filePath).toLowerCase();

    _selectedOriginalWavPath = path_helper.join(_appDir, '${fileName}_original_copy.wav');
    _selectedProcessedWavPath = path_helper.join(_appDir, '${fileName}_processed_full.wav'); // For full processed file

    try {
      final originalFile = File(filePath);
      if (!await originalFile.exists()) {
        throw Exception("选择的文件不存在: $filePath");
      }

      // 停止当前任何文件播放
      if (_isPlayingFile) {
        _isExpectedPlayerStop = true;
        await _player.stop();
        _isPlayingFile = false;
        _currentPlayingFilePath = null;
      }
      
      // 如果选择的文件不是WAV，则需要转换或提示。当前_loadAudioFile仅处理WAV。
      // 为了简化，我们先假设选择的就是WAV，或者在_loadAudioFile中处理转换/错误。
      // 此处直接复制到 _selectedOriginalWavPath
      await originalFile.copy(_selectedOriginalWavPath!);
      print('原始文件已复制到: $_selectedOriginalWavPath');
      
      // 清理旧的处理后文件（如果存在）
      final processedFullFile = File(_selectedProcessedWavPath!);
      if (await processedFullFile.exists()) {
        await processedFullFile.delete();
        print('旧的处理后文件已删除: $_selectedProcessedWavPath');
      }

      _completeOriginalAudio.clear(); // Clear any previous full audio data
      _completeProcessedAudio.clear();

      onStatusChanged?.call('文件选择完成: ${path_helper.basename(_selectedOriginalWavPath!)}');
      onStateChanged?.call();

    } catch (e) {
      onError?.call('准备音频文件路径失败: $e');
      _selectedAudioFilePath = null;
      _selectedOriginalWavPath = null;
      _selectedProcessedWavPath = null;
      onStateChanged?.call();
    }
  }

  /// 加载音频文件
  Future<Float32List> _loadAudioFile(String filePath, {int? expectedSampleRate}) async {
    // Modified to include robust WAV parsing for data chunk
    try {
        final file = File(filePath);
        if (!await file.exists()) throw Exception('音频文件不存在: $filePath');

        final fileBytes = await file.readAsBytes();
        print('加载文件: $filePath, 大小: ${fileBytes.length} bytes');

        if (fileBytes.length < 44) throw Exception('文件太小，可能不是有效的WAV文件');

        final ByteData headerBytes = ByteData.view(fileBytes.buffer, 0, 44);

        // Check RIFF and WAVE
        if (headerBytes.getUint32(0, Endian.big) != 0x52494646 || // RIFF
            headerBytes.getUint32(8, Endian.big) != 0x57415645) { // WAVE
            throw Exception('不是有效的WAV文件格式 (RIFF/WAVE)');
        }
        // Check fmt 
        if (headerBytes.getUint32(12, Endian.big) != 0x666d7420) { // "fmt "
             throw Exception('WAV文件缺少fmt块');
        }

        final int audioFormat = headerBytes.getUint16(20, Endian.little);
        if (audioFormat != 1) throw Exception('仅支持PCM格式的WAV文件 (format: $audioFormat)');
        
        final int numChannels = headerBytes.getUint16(22, Endian.little);
        if (numChannels != 1) print('警告: 音频文件不是单声道 (声道数: $numChannels), 将尝试作为单声道处理');

        final int sampleRate = headerBytes.getUint32(24, Endian.little);
        if (expectedSampleRate != null && sampleRate != expectedSampleRate) {
            print('警告: WAV文件采样率 ($sampleRate Hz) 与期望值 ($expectedSampleRate Hz) 不符. RNNoise期望 ${SAMPLE_RATE}Hz.');
            // For now, we proceed but RNNoise might not work optimally.
            // Ideally, resample here if needed, or reject.
        }
         if (sampleRate != SAMPLE_RATE) {
            print('警告: 文件采样率 ($sampleRate) 与RNNoise期望 ($SAMPLE_RATE)不符. 结果可能不佳.');
        }


        final int bitsPerSample = headerBytes.getUint16(34, Endian.little);
        if (bitsPerSample != 16) throw Exception('仅支持16位PCM WAV (位深度: $bitsPerSample)');

        // Find 'data' chunk
        int dataStartPosition = 12; // Default
        bool foundData = false;
        while(dataStartPosition < fileBytes.length - 8) {
            String chunkId = String.fromCharCodes(fileBytes.sublist(dataStartPosition, dataStartPosition + 4));
            int chunkSize = ByteData.view(fileBytes.buffer, dataStartPosition + 4, 4).getUint32(0, Endian.little);
            if (chunkId == 'data') {
                dataStartPosition += 8; // Move to start of data
                foundData = true;
                break;
            }
            dataStartPosition += (8 + chunkSize);
            // Ensure alignment if chunk sizes are odd (though typically not for WAV chunks)
            if (chunkSize % 2 != 0) dataStartPosition++;
        }

        if (!foundData) throw Exception('WAV文件找不到data数据块');
        if (dataStartPosition >= fileBytes.length) throw Exception('WAV数据块位置超出文件范围');
        
        final audioSampleBytes = fileBytes.sublist(dataStartPosition);
        final samples = Int16List.view(audioSampleBytes.buffer, audioSampleBytes.offsetInBytes, audioSampleBytes.lengthInBytes ~/ 2);
        
        final audioData = Float32List(samples.length);
        for (int i = 0; i < samples.length; i++) {
            audioData[i] = samples[i] / 32768.0;
        }
        print('音频文件加载成功: ${audioData.length}个样本 from $filePath');
        return audioData;
    } catch (e) {
        print('加载音频文件 $filePath 失败: $e');
        throw Exception('加载音频文件失败: $e');
    }
}


  Future<void> _processAudioDataStream(Float32List audioData, {bool accumulateToComplete = true}) async {
    final totalFrames = audioData.length ~/ FRAME_SIZE;
    onStatusChanged?.call('开始流式处理选择的文件，总帧数: $totalFrames');
    
    if (accumulateToComplete) {
      _completeOriginalAudio.clear(); 
      _completeProcessedAudio.clear();
    }

    List<Float32List> processedFramesForCurrentOp = [];

    for (int frameIndex = 0; frameIndex < totalFrames; frameIndex++) {
      if (_stopFileChunkProcessingLoop && !accumulateToComplete) break; // Allow stopping for chunk processing

      final startIdx = frameIndex * FRAME_SIZE;
      final endIdx = math.min(startIdx + FRAME_SIZE, audioData.length);
      final frameSizeActual = endIdx - startIdx;
      
      final inputFrame = Float32List(FRAME_SIZE);
      for (int i = 0; i < frameSizeActual; i++) {
        inputFrame[i] = audioData[startIdx + i];
      }
      if (frameSizeActual < FRAME_SIZE) { // Zero pad if last frame is incomplete
          for (int i = frameSizeActual; i < FRAME_SIZE; i++) inputFrame[i] = 0.0;
      }
      
      final result = _rnnoise.processFrames(inputFrame, 1);
      
      if (accumulateToComplete) {
        _completeOriginalAudio.add(Float32List.fromList(inputFrame));
        _completeProcessedAudio.add(Float32List.fromList(result.processedAudio));
      } else {
        processedFramesForCurrentOp.add(Float32List.fromList(result.processedAudio));
      }
      
      if (frameIndex % 100 == 0 || frameIndex == totalFrames - 1) {
        final progress = (frameIndex / totalFrames * 100).toInt();
        onStatusChanged?.call('处理进度: $progress% (${frameIndex + 1}/$totalFrames)');
        final processResult = AudioProcessResult(
          processedAudio: result.processedAudio, vadProbability: result.vadProbability,
          framesProcessed: frameIndex + 1, timestamp: DateTime.now(),
        );
        onAudioProcessed?.call(processResult);
      }
      
      if (frameIndex % 50 == 0) await Future.delayed(const Duration(milliseconds: 1));
    }
     if (!accumulateToComplete) {
      // This path is for chunk processing, caller will handle merged frames
      // For simplicity, let's return the merged frames of this operation if not accumulating globally
      // However, _processAndFeedChunks directly handles merging its chunks.
      // This `else` branch might be redundant if _processAudioDataStream is only called for full processing.
    }
  }

  Future<void> _saveSelectedProcessedWavFile({bool isStreamSave = false}) async {
    if (_completeProcessedAudio.isEmpty) {
      throw Exception('没有已处理的音频数据可保存 (_completeProcessedAudio is empty)');
    }
    if (_selectedProcessedWavPath == null) {
        throw Exception('目标已处理文件路径 (_selectedProcessedWavPath) 未设置');
    }
    try {
      final mergedAudio = _mergeAudioFrames(_completeProcessedAudio);
      await _saveAudioAsWav(mergedAudio, _selectedProcessedWavPath!);
      print('降噪结果保存完成: $_selectedProcessedWavPath (StreamSave: $isStreamSave)');
      if (isStreamSave) { // After streaming, clear the buffer as it's now saved.
        _completeProcessedAudio.clear();
        _completeOriginalAudio.clear(); 
      }
    } catch (e) {
      throw Exception('保存降噪后的音频文件失败: $e');
    }
  }

  void setDenoiseEnabledForStream(bool enabled) {
    _isDenoisingEnabledForStream = enabled;
    if (_isPlayingStream) { 
      _player.stop(); _isPlayingStream = false; _currentPlayingFilePath = null;
      onStatusChanged?.call('实时降噪已 ${_isDenoisingEnabledForStream ? "开启" : "关闭"}，请重新播放');
    } else {
      onStatusChanged?.call('实时降噪已 ${_isDenoisingEnabledForStream ? "开启" : "关闭"}');
    }
    onStateChanged?.call();
  }

  void setDenoiseEnabledForFile(bool enabled) async {
    _isDenoisingEnabledForFile = enabled;
    if (_isPlayingFile) { 
      _isExpectedPlayerStop = true; // Expect player to stop due to this action
      await _stopAndCleanupFileProcessing(); //This will stop player, clear chunks etc.
      onStatusChanged?.call('文件降噪已 ${_isDenoisingEnabledForFile ? "开启" : "关闭"}，请重新播放');
    } else {
      onStatusChanged?.call('文件降噪已 ${_isDenoisingEnabledForFile ? "开启" : "关闭"}');
    }
    onStateChanged?.call();
  }

  Future<void> toggleStreamPlayback() async {
    if (_isPlayingFile) {
       _isExpectedPlayerStop = true;
       await _stopAndCleanupFileProcessing();
    }

    if (_isPlayingStream) {
      _isExpectedPlayerStop = true;
      await _player.pause(); 
      _isPlayingStream = false;
      onStatusChanged?.call('实时音频暂停');
    } else {
      String? pathToPlay = _isDenoisingEnabledForStream ? _realtimeProcessedPath : _realtimeOriginalPath;
      String messagePrefix = _isDenoisingEnabledForStream ? '实时降噪音频' : '实时原始音频';
      
      if (pathToPlay == null || !await File(pathToPlay).exists()) {
        onError?.call('$messagePrefix 文件不存在，请先录制。'); return;
      }
      
      if (_currentPlayingFilePath == pathToPlay && _player.processingState != ProcessingState.completed) {
        await _player.play(); // Resume
      } else {
        await _playAudio(pathToPlay, messagePrefix);
      }
      _isPlayingStream = true;
    }
    onStateChanged?.call();
  }

  Future<void> _stopAndCleanupFileProcessing() async {
    _stopFileChunkProcessingLoop = true; // Signal background loop to stop
    if (_isChunkProcessingActive || _isPlayingFile) { // if chunk processing was active or file was playing
        _isExpectedPlayerStop = true;
        await _player.stop();
    }
    _isPlayingFile = false;
    _isFileProcessing = false; // General file processing state
    _isChunkProcessingActive = false; // Specifically for the background chunk processing task
    _currentPlayingFilePath = null;
    
    _concatenatingFileSource = null; // Clear the source
    _cleanupChunkFiles();
    onStateChanged?.call();
  }

  void _cleanupChunkFiles() {
      for (String p in _processedChunkFilePaths) { 
        try { File(p).deleteSync();} catch(e){print("Error deleting chunk $p: $e");} 
      }
      _processedChunkFilePaths.clear();
      
      // 清理当前临时文件（如果存在）
      if (_currentTempFilePath != null) {
        try { 
          File(_currentTempFilePath!).deleteSync();
          print("Deleted current temp file: $_currentTempFilePath");
        } catch(e) {
          print("Error deleting current temp file $_currentTempFilePath: $e");
        }
        _currentTempFilePath = null;
      }
      
      // 清理内存缓冲队列
      _audioBufferQueue.clear();
      _bufferPlaybackIndex = 0;
      print("_cleanupChunkFiles: Cleared chunk files and buffer queue (Data URI memory mode)");
  }

  Future<void> toggleFilePlayback() async {
    print("toggleFilePlayback called. isPlayingStream: $_isPlayingStream, isPlayingFile: $_isPlayingFile, isDenoisingEnabledForFile: $_isDenoisingEnabledForFile");
    if (_isPlayingStream) {
        _isExpectedPlayerStop = true;
        await _player.stop(); _isPlayingStream = false; _currentPlayingFilePath = null;
        onStatusChanged?.call('已停止实时流播放以播放文件');
        print("Stopped stream playback to play file.");
    }

    if (_selectedOriginalWavPath == null) {
      onError?.call('请先选择一个音频文件');
      print("toggleFilePlayback: No selected original WAV path.");
      return;
    }

    if (_isPlayingFile) { // Pause request
      print("toggleFilePlayback: Pausing file playback. Current mode: ${_isDenoisingEnabledForFile ? 'Denoised' : 'Original'}");
      if (_isDenoisingEnabledForFile) {
        _stopFileChunkProcessingLoop = true; 
        print("toggleFilePlayback: Set _stopFileChunkProcessingLoop = true for denoised pause.");
      }
      print("toggleFilePlayback: Calling _player.pause()...");
      _isExpectedPlayerStop = true;
      await _player.pause();
      print("toggleFilePlayback: _player.pause() completed.");
      _isPlayingFile = false; 
      _isFileProcessing = false; // General processing should also be considered stopped.
      onStatusChanged?.call('文件音频暂停');
      print("toggleFilePlayback: Pause state updated. _isPlayingFile=false, _isFileProcessing=false, _stopFileChunkProcessingLoop=$_stopFileChunkProcessingLoop");
    } else { // Play or Resume request
      print("toggleFilePlayback: Starting or resuming file playback.");
      
      if (_isDenoisingEnabledForFile) {
        onStatusChanged?.call('文件降噪音频 (分块流式) 准备中...');
        print("toggleFilePlayback: Denoising enabled. Preparing for chunked playback.");
        
        // 检查是否需要重新设置播放源
        if (_currentPlayingFilePath != _selectedOriginalWavPath || !_player.playing) {
             print("toggleFilePlayback: Preparing for ${_useMemoryStreamPlayback ? 'memory stream' : 'concatenating'} playback.");
             if(_player.playing) {
                _isExpectedPlayerStop = true;
                await _player.stop();
             }
             _cleanupChunkFiles();
             
             if (_useMemoryStreamPlayback) {
                // 内存流播放：不需要预先设置AudioSource，在_consumeAudioBuffersMemoryStream中设置
                print("toggleFilePlayback: Preparing for memory stream playback (no pre-setup needed).");
             } else {
                // 传统方式：使用ConcatenatingAudioSource
                _concatenatingFileSource = ConcatenatingAudioSource(children: [], useLazyPreparation: true);
                try {
                   await _player.setAudioSource(_concatenatingFileSource!, initialIndex: 0, preload: true);
                   print("toggleFilePlayback: Set concatenating audio source to player.");
                } catch (e) {
                   print("Error setting concatenating audio source: $e");
                   onError?.call("播放器设置失败: $e");
                   _isPlayingFile = false;
                   _isFileProcessing = false;
                   onStateChanged?.call();
                   return;
                }
             }
        } else {
          print("toggleFilePlayback: Resuming with existing playback mode.");
        }
        _currentPlayingFilePath = _selectedOriginalWavPath; // Mark what we are conceptually playing
        
        try {
            _isPlayingFile = true; // Set to true BEFORE starting processing
            _isFileProcessing = true; // Indicate that background processing will start
            print("toggleFilePlayback: Starting playback mode: ${_useMemoryStreamPlayback ? 'Memory Stream' : 'Concatenating Source'}");
            
                         if (_useMemoryStreamPlayback) {
                // 优化的动态文件模式：只启动处理，消费会在_startBufferedPlayback中自动启动
                print("toggleFilePlayback: Starting optimized dynamic file processing.");
                _processAndFeedFileChunks(); // Start background processing (don't await)
             } else {
                // 传统模式：先启动播放器，然后开始处理
                print("toggleFilePlayback: Calling player.play() for concatenating source.");
                await _player.play();
                _processAndFeedFileChunks(); // Start background processing (don't await)
             }
            
            print("toggleFilePlayback: Playback started successfully. _isPlayingFile=true, _isFileProcessing=true");
        } catch (e) {
            print("Error starting playback: $e");
            onError?.call("播放器启动失败: $e");
            _isPlayingFile = false; // Ensure state is correct on failure
            _isFileProcessing = false;
            await _stopAndCleanupFileProcessing(); 
            onStateChanged?.call();
            return;
        }
      } else { // Play original WAV directly
        onStatusChanged?.call('文件原始音频准备中...');
        print("toggleFilePlayback: Denoising disabled. Playing original directly.");
        await _stopAndCleanupFileProcessing(); // Ensure any chunk processing is stopped

        try {
            // Check if we are resuming a paused original file
            if (_currentPlayingFilePath == _selectedOriginalWavPath && 
                _player.processingState != ProcessingState.completed &&
                !_player.playing && // It was paused
                _player.audioSource != null) { // And source is still set
               print("toggleFilePlayback: Resuming original non-denoised file.");
               _isPlayingFile = true; // Set BEFORE calling play to ensure UI updates immediately
               await _player.play(); 
            } else {
               print("toggleFilePlayback: Playing original non-denoised file from start.");
               _currentPlayingFilePath = _selectedOriginalWavPath;
               _isPlayingFile = true; // Set BEFORE calling play to ensure UI updates immediately
               await _player.setAudioSource(AudioSource.uri(Uri.file(_selectedOriginalWavPath!)));
               await _player.play();
               onStatusChanged?.call('文件原始音频 开始播放');
            }
        } catch (e) {
            print("Error playing original file: $e");
            onError?.call('播放原始文件失败: $e');
            _isPlayingFile = false; // Ensure state is correct on failure
            _currentPlayingFilePath = null; 
        }
      }
    }
    // Diagnostic print before calling onStateChanged
    print("toggleFilePlayback END state: _isPlayingFile: $_isPlayingFile, _isFileProcessing: $_isFileProcessing, _isDenoisingEnabledForStream: $_isDenoisingEnabledForStream, _isDenoisingEnabledForFile: $_isDenoisingEnabledForFile, _stopFileChunkProcessingLoop: $_stopFileChunkProcessingLoop, _currentPlayingFilePath: $_currentPlayingFilePath");
    onStateChanged?.call();
  }
  
  Future<void> _processAndFeedFileChunks() async {
    print("_processAndFeedFileChunks started. Selected Original Path: $_selectedOriginalWavPath, isPlayingFile: $_isPlayingFile");
    if (_selectedOriginalWavPath == null || !_isPlayingFile) { 
      print("_processAndFeedFileChunks: Conditions not met to start (no path or not playing). Bailing out.");
      _isChunkProcessingActive = false;
      _isFileProcessing = false;
       onStateChanged?.call();
      return;
    }

    _isChunkProcessingActive = true;
    _isFileProcessing = true; 
    _stopFileChunkProcessingLoop = false;
    _audioBufferQueue.clear(); // 清空缓冲队列
    _bufferPlaybackIndex = 0;
    onStateChanged?.call(); 

    RandomAccessFile? raf;
    int chunkIndex = 0;
    _completeOriginalAudio.clear(); 
    _completeProcessedAudio.clear();
    int totalAudioBytes = 0;

    try {
      print("_processAndFeedFileChunks: Opening file: $_selectedOriginalWavPath");
      raf = await File(_selectedOriginalWavPath!).open(mode: FileMode.read);
      print("_processAndFeedFileChunks: File opened. Length: ${await raf.length()}");
      
      // WAV Header Parsing（简化版本）
      int dataStartPosition = 44; 
      if (await raf.length() >= 44) {
          final headerCheckBytes = await raf.read(math.min(100, await raf.length())); 
          await raf.setPosition(0); 

          if (String.fromCharCodes(headerCheckBytes.sublist(0,4)) != "RIFF" || 
              String.fromCharCodes(headerCheckBytes.sublist(8,12)) != "WAVE") {
              throw Exception("Selected file is not a valid WAV file for chunking.");
          }
          
          // 寻找data chunk
          int searchPos = 12;
          bool foundData = false;
          while(searchPos < headerCheckBytes.length - 8) {
              String chunkId = String.fromCharCodes(headerCheckBytes.sublist(searchPos, searchPos + 4));
              if (searchPos + 8 > headerCheckBytes.length) break; 
              int chunkSize = ByteData.view(headerCheckBytes.buffer, headerCheckBytes.offsetInBytes + searchPos + 4, 4).getUint32(0, Endian.little);
              
              if (chunkId == 'data') {
                  dataStartPosition = searchPos + 8;
                  foundData = true;
                  print("_processAndFeedFileChunks: Found 'data' chunk starting at $dataStartPosition");
                  break;
              }
              searchPos += (8 + chunkSize);
              if (chunkSize % 2 != 0 && searchPos < headerCheckBytes.length) searchPos++; 
          }
          if (!foundData) {
             throw Exception("Could not find 'data' chunk in WAV for chunking.");
          }
      } else {
        throw Exception("File too short to be a valid WAV for chunking.");
      }
      
      await raf.setPosition(dataStartPosition);
      totalAudioBytes = await raf.length() - dataStartPosition;
      print("_processAndFeedFileChunks: Total audio data bytes: $totalAudioBytes");
      
      int samplesPerChunk = SAMPLE_RATE * _chunkDurationSeconds; // 1秒 = 48000样本
      int bytesPerChunkTarget = samplesPerChunk * 2; // 16位PCM

      // 开始双缓冲处理循环
      while (totalAudioBytes > 0 && !_stopFileChunkProcessingLoop && _isPlayingFile) {
        onStatusChanged?.call("处理音频块 ${chunkIndex + 1}... (${(chunkIndex * _chunkDurationSeconds)}s)");
        print("_processAndFeedFileChunks: Processing chunk ${chunkIndex + 1}. Remaining bytes: $totalAudioBytes");

        // 如果缓冲队列太满，等待播放消费
        while (_audioBufferQueue.length >= _maxBufferQueueSize && !_stopFileChunkProcessingLoop && _isPlayingFile) {
          print("_processAndFeedFileChunks: Buffer queue full (${_audioBufferQueue.length}), waiting...");
          await Future.delayed(Duration(milliseconds: 200));
        }

        if (_stopFileChunkProcessingLoop || !_isPlayingFile) break;

        int bytesToRead = math.min(bytesPerChunkTarget, totalAudioBytes);
        if (bytesToRead <= 0) break;
        
        Uint8List pcmChunkBytes = await raf.read(bytesToRead);
        if (pcmChunkBytes.isEmpty) break;
        
        totalAudioBytes -= pcmChunkBytes.length; 

        // 处理音频块
        final processedChunk = await _processAudioChunk(pcmChunkBytes, chunkIndex);
        
        if (processedChunk != null && !_stopFileChunkProcessingLoop && _isPlayingFile) {
          // 创建WAV格式的音频数据（内存中）
          final wavData = _createWavFromPCM(processedChunk, SAMPLE_RATE, 1, 16);
          
          // 添加到内存缓冲队列
          _audioBufferQueue.add(wavData);
          print("_processAndFeedFileChunks: Added chunk $chunkIndex to buffer queue. Queue size: ${_audioBufferQueue.length}");
          
          // 如果这是第一个块，立即开始播放
          if (chunkIndex == 0) {
            _startBufferedPlayback();
          }
        }
        
        chunkIndex++;
        await Future.delayed(Duration(milliseconds: 50)); // 小间隔避免阻塞UI
      }
      
      print("_processAndFeedFileChunks: Processing completed. Total chunks: $chunkIndex");
      onStatusChanged?.call("音频块处理完成，总计${chunkIndex}个块");
      
    } catch (e, s) {
      onError?.call("处理/读取音频块失败: $e");
      print("Error in _processAndFeedFileChunks: $e\nStackTrace: $s");
    } finally {
      await raf?.close();
      _isChunkProcessingActive = false;
      if (_stopFileChunkProcessingLoop || !_isPlayingFile) {
          _isFileProcessing = false;
          print("_processAndFeedFileChunks: Setting _isFileProcessing to false due to stop/not playing.");
      } else if (totalAudioBytes <= 0) {
          print("_processAndFeedFileChunks: All data processed. _isFileProcessing remains $_isFileProcessing");
      }
      print("_processAndFeedFileChunks finished. Queue size: ${_audioBufferQueue.length}");
      onStateChanged?.call();
    }
  }

  /// 处理单个音频块的降噪
  Future<Uint8List?> _processAudioChunk(Uint8List pcmChunkBytes, int chunkIndex) async {
    try {
      List<Float32List> originalFramesInChunk = [];
      List<Float32List> processedFramesInChunk = [];
      
      ByteData pcmChunkByteData = ByteData.view(pcmChunkBytes.buffer, pcmChunkBytes.offsetInBytes, pcmChunkBytes.lengthInBytes);
      int currentByteOffset = 0;

      // 按RNNoise帧大小处理
      while(currentByteOffset + (FRAME_SIZE * 2) <= pcmChunkByteData.lengthInBytes) {
          if (_stopFileChunkProcessingLoop || !_isPlayingFile) break; 

          final inputFrameInt16 = Int16List(FRAME_SIZE);
          for(int i = 0; i < FRAME_SIZE; i++){
              inputFrameInt16[i] = pcmChunkByteData.getInt16(currentByteOffset + i * 2, Endian.little);
          }
          currentByteOffset += FRAME_SIZE * 2;
          
          final inputFrameF32 = Float32List(FRAME_SIZE);
          for (int i = 0; i < FRAME_SIZE; i++) inputFrameF32[i] = inputFrameInt16[i] / 32768.0;
          
          originalFramesInChunk.add(inputFrameF32);
          final result = _rnnoise.processFrames(inputFrameF32, 1);
          processedFramesInChunk.add(result.processedAudio);
      }

      if (processedFramesInChunk.isNotEmpty) {
        // 将所有处理后的帧合并为一个音频块
        Float32List processedChunkF32 = _mergeAudioFrames(processedFramesInChunk);
        _completeOriginalAudio.addAll(originalFramesInChunk); 
        _completeProcessedAudio.addAll(processedFramesInChunk);
        
        // 转换为PCM数据
        final pcmData = Uint8List(processedChunkF32.length * 2);
        for (int i = 0; i < processedChunkF32.length; i++) {
          int sample = (processedChunkF32[i] * 32767).round().clamp(-32768, 32767);
          pcmData[i * 2] = sample & 0xFF;
          pcmData[i * 2 + 1] = (sample >> 8) & 0xFF;
        }
        
        return pcmData;
      }
      
      return null;
    } catch (e) {
      print("Error processing audio chunk $chunkIndex: $e");
      return null;
    }
  }

  /// 从PCM数据创建WAV格式的字节数据（内存中）
  Uint8List _createWavFromPCM(Uint8List pcmData, int sampleRate, int channels, int bitsPerSample) {
    final dataSize = pcmData.length;
    final totalSize = 44 + dataSize;
    
    final wavData = Uint8List(totalSize);
    final wavView = ByteData.view(wavData.buffer);
    
    // WAV文件头
    // RIFF chunk
    wavData.setRange(0, 4, 'RIFF'.codeUnits);
    wavView.setUint32(4, totalSize - 8, Endian.little);
    wavData.setRange(8, 12, 'WAVE'.codeUnits);
    
    // fmt chunk
    wavData.setRange(12, 16, 'fmt '.codeUnits);
    wavView.setUint32(16, 16, Endian.little); // chunk size
    wavView.setUint16(20, 1, Endian.little); // PCM format
    wavView.setUint16(22, channels, Endian.little);
    wavView.setUint32(24, sampleRate, Endian.little);
    wavView.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little); // byte rate
    wavView.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little); // block align
    wavView.setUint16(34, bitsPerSample, Endian.little);
    
    // data chunk
    wavData.setRange(36, 40, 'data'.codeUnits);
    wavView.setUint32(40, dataSize, Endian.little);
    wavData.setRange(44, 44 + dataSize, pcmData);
    
    return wavData;
  }

  /// 开始缓冲播放
  void _startBufferedPlayback() async {
    if (_audioBufferQueue.isEmpty) return;
    
    print("_startBufferedPlayback: Starting ${_useMemoryStreamPlayback ? 'memory stream' : 'file-based'} playback with ${_audioBufferQueue.length} buffers");
    
    // 启动播放消费循环
    _consumeAudioBuffers();
  }

  /// 消费音频缓冲队列
  void _consumeAudioBuffers() async {
    if (_useMemoryStreamPlayback) {
      // 使用完全基于内存的流播放
      _consumeAudioBuffersMemoryStream();
    } else {
      // 使用传统的临时文件方式（备用）
      _consumeAudioBuffersFileMode();
    }
  }

  /// 边处理边播放的渐进式内存流播放
  void _consumeAudioBuffersMemoryStream() async {
    print("_consumeAudioBuffersMemoryStream: Starting progressive streaming playback");
    
    List<int> completeAudioData = [];
    bool hasStartedPlayback = false;
    int chunksProcessedSinceLastUpdate = 0;
    const int initialBatchSize = 3; // 初始批次：收集3个chunk再播放，确保足够长度
    const int updateBatchSize = 2; // 后续更新：每2个chunk更新一次
    Duration lastPlayPosition = Duration.zero;
    
    // 渐进式播放：先播放初始数据，然后分批更新
    while (_isPlayingFile && !_stopFileChunkProcessingLoop) {
      if (_audioBufferQueue.isNotEmpty) {
        final audioData = _audioBufferQueue.removeFirst();
        
        try {
          if (!hasStartedPlayback) {
            // 第一批：收集足够的初始数据再开始播放
            completeAudioData = audioData.toList();
            int initialBatchCount = 1;
            _bufferPlaybackIndex++;
            
            print("_consumeAudioBuffersMemoryStream: Collecting initial batch, got chunk 1 (${audioData.length} bytes)");
            
            // 等待并收集初始批次的chunks
            while (initialBatchCount < initialBatchSize) {
              // 等待更多chunks
              while (_audioBufferQueue.isEmpty && _isChunkProcessingActive) {
                await Future.delayed(Duration(milliseconds: 50));
                print("_consumeAudioBuffersMemoryStream: Waiting for chunk ${initialBatchCount + 1} for initial batch...");
              }
              
              if (_audioBufferQueue.isNotEmpty) {
                final nextChunk = _audioBufferQueue.removeFirst();
                final pcmData = nextChunk.sublist(44);
                completeAudioData.addAll(pcmData);
                initialBatchCount++;
                _bufferPlaybackIndex++;
                print("_consumeAudioBuffersMemoryStream: Added chunk $initialBatchCount to initial batch (${nextChunk.length} bytes)");
              } else if (!_isChunkProcessingActive) {
                print("_consumeAudioBuffersMemoryStream: Processing completed, starting with available ${initialBatchCount} chunks");
                break;
              }
            }
            
            // 开始播放初始批次
            await _startProgressivePlayback(completeAudioData);
            hasStartedPlayback = true;
            chunksProcessedSinceLastUpdate = 0; // 重置计数器
            print("_consumeAudioBuffersMemoryStream: Started progressive playback with $initialBatchCount chunks (${completeAudioData.length} bytes)");
          } else {
            // 后续块：累积到批次大小后更新
            final pcmData = audioData.sublist(44);
            completeAudioData.addAll(pcmData);
            chunksProcessedSinceLastUpdate++;
            _bufferPlaybackIndex++;
            
            print("_consumeAudioBuffersMemoryStream: Accumulated chunk ${_bufferPlaybackIndex} (${pcmData.length} bytes, batch: ${chunksProcessedSinceLastUpdate}/${updateBatchSize}, total: ${completeAudioData.length} bytes)");
            
            // 达到批次大小或者是最后一批，进行更新
            if (chunksProcessedSinceLastUpdate >= updateBatchSize || 
                (_audioBufferQueue.isEmpty && !_isChunkProcessingActive)) {
              
              await _updateProgressivePlayback(completeAudioData, lastPlayPosition);
              chunksProcessedSinceLastUpdate = 0;
              print("_consumeAudioBuffersMemoryStream: Updated playback with batch of $updateBatchSize chunks");
            }
          }
          
          // 记录当前播放位置，用于恢复
          if (_player.duration != null && _player.position.inMilliseconds > 0) {
            lastPlayPosition = _player.position;
          }
          
          // 适当延迟，让播放器有时间处理
          await Future.delayed(Duration(milliseconds: 30));
        } catch (e) {
          print("Error in progressive playback: $e");
        }
      } else {
        // 检查是否处理完成
        if (!_isChunkProcessingActive && hasStartedPlayback && chunksProcessedSinceLastUpdate > 0) {
          // 处理剩余的chunks
          await _updateProgressivePlayback(completeAudioData, lastPlayPosition);
          print("_consumeAudioBuffersMemoryStream: Final update with remaining ${chunksProcessedSinceLastUpdate} chunks");
          break;
        }
        // 等待新的缓冲数据
        print("_consumeAudioBuffersMemoryStream: Waiting for more chunks... Queue size: ${_audioBufferQueue.length}, Processing active: $_isChunkProcessingActive, Playback started: $hasStartedPlayback, Chunks since update: $chunksProcessedSinceLastUpdate");
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
    
    print("_consumeAudioBuffersMemoryStream: Progressive streaming playback completed (Final queue size: ${_audioBufferQueue.length})");
  }
  
  /// 开始渐进式播放
  Future<void> _startProgressivePlayback(List<int> initialAudioData) async {
    try {
      // 更新WAV头
      final totalDataSize = initialAudioData.length - 44;
      _updateWavHeaderInMemory(initialAudioData, totalDataSize);
      
      // 转换为Data URI并开始播放
      final base64Audio = base64Encode(initialAudioData);
      final dataUri = 'data:audio/wav;base64,$base64Audio';
      
      await _player.setAudioSource(AudioSource.uri(Uri.parse(dataUri)));
      await _player.play();
      print("_startProgressivePlayback: Initial playback started (${initialAudioData.length} bytes)");
    } catch (e) {
      print("Error starting progressive playback: $e");
      onError?.call("渐进式播放启动失败: $e");
    }
  }
  
  /// 更新渐进式播放
  Future<void> _updateProgressivePlayback(List<int> updatedAudioData, Duration lastPosition) async {
    try {
      // 更新WAV头
      final totalDataSize = updatedAudioData.length - 44;
      _updateWavHeaderInMemory(updatedAudioData, totalDataSize);
      
      // 保存当前播放状态
      final wasPlaying = _player.playing;
      final currentPosition = _player.position;
      
      // 转换为新的Data URI
      final base64Audio = base64Encode(updatedAudioData);
      final dataUri = 'data:audio/wav;base64,$base64Audio';
      
      // 快速更新音频源
      await _player.setAudioSource(AudioSource.uri(Uri.parse(dataUri)));
      
      // 恢复播放位置和状态
      if (currentPosition.inMilliseconds > 0) {
        await _player.seek(currentPosition);
      }
      
      if (wasPlaying) {
        await _player.play();
      }
      
      print("_updateProgressivePlayback: Updated audio source (${updatedAudioData.length} bytes) at position ${currentPosition.inSeconds}s");
    } catch (e) {
      print("Error updating progressive playback: $e");
      // 如果更新失败，尝试继续播放原有内容
    }
  }

  /// 在内存中更新WAV文件头
  void _updateWavHeaderInMemory(List<int> wavData, int dataSize) {
    // 更新文件总大小 (位置4-7)
    final totalSize = dataSize + 36; // 36 = 44 - 8 (RIFF header)
    wavData[4] = totalSize & 0xFF;
    wavData[5] = (totalSize >> 8) & 0xFF;
    wavData[6] = (totalSize >> 16) & 0xFF;
    wavData[7] = (totalSize >> 24) & 0xFF;
    
    // 更新数据块大小 (位置40-43)
    wavData[40] = dataSize & 0xFF;
    wavData[41] = (dataSize >> 8) & 0xFF;
    wavData[42] = (dataSize >> 16) & 0xFF;
    wavData[43] = (dataSize >> 24) & 0xFF;
  }

  /// 更新文件中WAV文件头的大小信息
  Future<void> _updateWavHeaderInFile(File file, int dataSize) async {
    RandomAccessFile raf = await file.open(mode: FileMode.writeOnly);
    try {
      // 更新文件总大小 (位置4-7)
      final totalSize = dataSize + 36; // 36 = 44 - 8 (RIFF header)
      await raf.setPosition(4);
      await raf.writeByte(totalSize & 0xFF);
      await raf.writeByte((totalSize >> 8) & 0xFF);
      await raf.writeByte((totalSize >> 16) & 0xFF);
      await raf.writeByte((totalSize >> 24) & 0xFF);
      
      // 更新数据块大小 (位置40-43)
      await raf.setPosition(40);
      await raf.writeByte(dataSize & 0xFF);
      await raf.writeByte((dataSize >> 8) & 0xFF);
      await raf.writeByte((dataSize >> 16) & 0xFF);
      await raf.writeByte((dataSize >> 24) & 0xFF);
      
      await raf.flush();
    } finally {
      await raf.close();
    }
  }

  /// 更新WAV文件头中的大小信息
  void _updateWavHeader(List<int> wavData, int dataSize) {
    // 更新文件总大小 (位置4-7)
    final totalSize = dataSize + 36; // 36 = 44 - 8 (RIFF header)
    wavData[4] = totalSize & 0xFF;
    wavData[5] = (totalSize >> 8) & 0xFF;
    wavData[6] = (totalSize >> 16) & 0xFF;
    wavData[7] = (totalSize >> 24) & 0xFF;
    
    // 更新数据块大小 (位置40-43)
    wavData[40] = dataSize & 0xFF;
    wavData[41] = (dataSize >> 8) & 0xFF;
    wavData[42] = (dataSize >> 16) & 0xFF;
    wavData[43] = (dataSize >> 24) & 0xFF;
  }

  /// 基于临时文件的音频消费（备用方式）
  void _consumeAudioBuffersFileMode() async {
    while (_isPlayingFile && !_stopFileChunkProcessingLoop) {
      if (_audioBufferQueue.isNotEmpty) {
        final audioData = _audioBufferQueue.removeFirst();
        
        // 创建临时文件用于播放（只在播放时创建，播放后删除）
        final tempFile = File(path_helper.join(_appDir, "temp_chunk_${DateTime.now().millisecondsSinceEpoch}.wav"));
        await tempFile.writeAsBytes(audioData);
        
        try {
          // 添加到播放队列
          if (_concatenatingFileSource != null && _isPlayingFile) {
            await _concatenatingFileSource!.add(AudioSource.uri(Uri.file(tempFile.path)));
            print("_consumeAudioBuffersFileMode: Added buffer ${_bufferPlaybackIndex} to player");
            _bufferPlaybackIndex++;
            
            // 延迟删除临时文件（播放完成后）
            Future.delayed(Duration(seconds: _chunkDurationSeconds + 2), () {
              if (tempFile.existsSync()) {
                tempFile.deleteSync();
              }
            });
          }
        } catch (e) {
          print("Error adding buffer to player: $e");
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
          }
        }
      } else {
        // 等待新的缓冲数据
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
    print("_consumeAudioBuffersFileMode: File mode playback consumption stopped");
  }

  /// 释放资源
  Future<void> dispose() async {
    try {
      // 停止所有活动
      if (_isStreamProcessing) {
        await stopStreamProcessing();
      }
      if (_isRecording) {
        await stopRecording();
      }
      
      // 停止文件处理并清理资源
      await _stopAndCleanupFileProcessing();
      
      // 清理RNNoise状态
      _rnnoise.cleanupState();
      
      // 取消定时器
      _audioSaveTimer?.cancel();
      _audioReadTimer?.cancel();
      
      // 取消订阅
      await _audioDataSubscription?.cancel();
      
      // 关闭音频流控制器
      await _audioStreamController?.close();
      
      // 释放播放器
      // await _originalPlayer.dispose(); // 移除
      // await _processedPlayer.dispose(); // 移除
      await _player.dispose(); // 释放统一播放器

      // 释放录音器
      await _recorder.dispose();
      
      // 释放流处理器
      _streamProcessor?.dispose();
      
      _isInitialized = false;
      
    } catch (e) {
      print('释放资源时出错: $e');
    }
  }
} 







