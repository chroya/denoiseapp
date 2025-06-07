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
        final bool wasPlayingFile = _isPlayingFile;

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
        _currentPlayingFilePath = null;
        
        if (wasPlayingStream) {
          onStatusChanged?.call('实时音频播放完成');
          print('实时音频播放完成');
        }
        if (wasPlayingFile && !_isPlayingFile) {
          onStatusChanged?.call('文件音频播放完成');
          print('文件音频播放完成');
        }
        onStateChanged?.call();
      } else if (state.processingState == ProcessingState.ready && !state.playing) {
        // Handle pause state if needed, or rely on explicit pause calls
      }
    });
    _player.playingStream.listen((playing) {
        if (_isExpectedPlayerStop) { 
            _isExpectedPlayerStop = false;
            print("Player stopped as expected. Ignoring playingStream update for this event.");
            return;
        }

        if (!playing && (_isPlayingStream || _isPlayingFile)) {
            print("Player stopped unexpectedly. Updating state.");
            _isPlayingStream = false;
            _isPlayingFile = false;
            _isFileProcessing = false;
            _currentPlayingFilePath = null;
            onStateChanged?.call();
        }
    });

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
      _rawAudioBuffer.clear();
      _processedAudioBuffer.clear();
      _originalAudioBuffer.clear();
      _completeProcessedAudio.clear();
      _completeOriginalAudio.clear();
      
      _audioStreamController = StreamController<Uint8List>.broadcast();
      _setupAudioStreamProcessing();
      
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: SAMPLE_RATE,
          numChannels: 1,
          bitRate: 16,
        ),
        path: _recordingPath,
      );
      
      await _startAudioStreamReading();
      
      _isStreamProcessing = true;
      _isRecording = true;
      
      _startAudioSaveTimer();
      
      onStatusChanged?.call('开始实时流处理');
      onStateChanged?.call();
      
    } catch (e) {
      onError?.call('启动实时流处理失败: $e');
      throw Exception('启动实时流处理失败: $e');
    }
  }

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

  Future<void> _startAudioStreamReading() async {
    _audioFileReadPosition = 44;
    
    _audioReadTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isStreamProcessing) {
        timer.cancel();
        return;
      }
      await _readAudioDataFromFile();
    });
  }

  Future<void> _readAudioDataFromFile() async {
    try {
      final file = File(_recordingPath);
      if (!await file.exists()) {
        return;
      }
      
      final fileBytes = await file.readAsBytes();
      
      if (fileBytes.length <= 44) {
        return;
      }
      
      if (_audioFileReadPosition == 44) {
        final riffHeader = String.fromCharCodes(fileBytes.sublist(0, 4));
        final waveHeader = String.fromCharCodes(fileBytes.sublist(8, 12));
        
        if (riffHeader != 'RIFF' || waveHeader != 'WAVE') {
          print('警告：文件可能不是有效的WAV格式');
        }
        
        int dataStart = 44;
        
        for (int i = 12; i < fileBytes.length - 8; i += 4) {
          final chunkId = String.fromCharCodes(fileBytes.sublist(i, i + 4));
          if (chunkId == 'data') {
            dataStart = i + 8;
            break;
          }
        }
        
        _audioFileReadPosition = dataStart;
        print('WAV文件数据开始位置: $dataStart');
      }
      
      if (fileBytes.length <= _audioFileReadPosition) {
        return;
      }
      
      const samplesToRead = SAMPLE_RATE ~/ 10;
      const bytesToRead = samplesToRead * 2;
      final endPos = math.min(_audioFileReadPosition + bytesToRead, fileBytes.length);
      
      if (endPos <= _audioFileReadPosition) {
        return;
      }
      
      final actualBytesToRead = ((endPos - _audioFileReadPosition) ~/ 2) * 2;
      final actualEndPos = _audioFileReadPosition + actualBytesToRead;
      
      if (actualBytesToRead < 2) {
        return;
      }
      
      final audioBytes = fileBytes.sublist(_audioFileReadPosition, actualEndPos);
      _audioFileReadPosition = actualEndPos;
      
      if (audioBytes.isNotEmpty) {
        _audioStreamController?.add(Uint8List.fromList(audioBytes));
      }
      
    } catch (e) {
      print('读取音频文件数据失败: $e');
    }
  }

  void _processAudioStreamData(Uint8List audioData) {
    try {
      final samples = Int16List.view(audioData.buffer);
      _rawAudioBuffer.addAll(samples);
      
      while (_rawAudioBuffer.length >= FRAME_SIZE) {
        final frameData = _rawAudioBuffer.take(FRAME_SIZE).toList();
        _rawAudioBuffer.removeRange(0, FRAME_SIZE);
        
        final inputFrame = Float32List(FRAME_SIZE);
        for (int i = 0; i < FRAME_SIZE; i++) {
          inputFrame[i] = frameData[i] / 32768.0;
        }
        
        final result = _rnnoise.processFrames(inputFrame, 1);
        
        if (_completeProcessedAudio.length % 100 == 0) {
          final inputRMS = _calculateRMS(inputFrame);
          final outputRMS = _calculateRMS(result.processedAudio);
          print('FFI处理验证 - 帧数: ${_completeProcessedAudio.length}, '
                '输入RMS: ${inputRMS.toStringAsFixed(4)}, '
                '输出RMS: ${outputRMS.toStringAsFixed(4)}, '
                'VAD概率: ${result.vadProbability.toStringAsFixed(3)}');
        }
        
        _originalAudioBuffer.add(inputFrame);
        _processedAudioBuffer.add(result.processedAudio);
        _completeOriginalAudio.add(Float32List.fromList(inputFrame));
        _completeProcessedAudio.add(Float32List.fromList(result.processedAudio));
        
        if (_originalAudioBuffer.length > _maxBufferSize) {
          _originalAudioBuffer.removeAt(0);
        }
        if (_processedAudioBuffer.length > _maxBufferSize) {
          _processedAudioBuffer.removeAt(0);
        }
        
        final processResult = AudioProcessResult(
          processedAudio: result.processedAudio,
          vadProbability: result.vadProbability,
          framesProcessed: _completeProcessedAudio.length,
          timestamp: DateTime.now(),
        );
        
        onAudioProcessed?.call(processResult);
      }
      
    } catch (e) {
      onError?.call('音频流处理失败: $e');
    }
  }
  
  Future<void> stopStreamProcessing() async {
    if (!_isStreamProcessing) return;
    
    try {
      await _recorder.stop();
      _audioReadTimer?.cancel();
      _audioReadTimer = null;
      await _audioDataSubscription?.cancel();
      _audioDataSubscription = null;
      await _audioStreamController?.close();
      _audioStreamController = null;
      _audioSaveTimer?.cancel();
      _audioSaveTimer = null;
      
      if (_isPlayingStream) {
        _isExpectedPlayerStop = true;
        await _player.stop();
        _isPlayingStream = false;
        _currentPlayingFilePath = null;
      }

      _isStreamProcessing = false;
      _isRecording = false;
      
      await _saveFinalAudioFiles();
      _analyzeAudioDifference();
      
      onStatusChanged?.call('停止实时流处理');
      onStateChanged?.call();
      
    } catch (e) {
      onError?.call('停止实时流处理失败: $e');
      throw Exception('停止实时流处理失败: $e');
    }
  }

  Future<void> _saveFinalAudioFiles() async {
    if (_completeProcessedAudio.isEmpty || _completeOriginalAudio.isEmpty) {
      return;
    }
    
    try {
      final processedAudio = _mergeAudioFrames(_completeProcessedAudio);
      final originalAudio = _mergeAudioFrames(_completeOriginalAudio);
      
      await _saveAudioAsWav(processedAudio, _realtimeProcessedPath);
      await _saveAudioAsWav(originalAudio, _realtimeOriginalPath);
      
      print('音频文件保存完成 - 原始音频: ${originalAudio.length}样本, 处理后音频: ${processedAudio.length}样本');
      
    } catch (e) {
      print('保存最终音频文件失败: $e');
    }
  }

  Future<void> startRecording() async {
    if (!_isInitialized || !_isRecorderInitialized || _isRecording) {
      onError?.call('录音器未初始化或正在录音');
      return;
    }
    
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
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

  void _startAudioSaveTimer() {
    _audioSaveTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isStreamProcessing) {
        timer.cancel();
        return;
      }
      
      _saveRecentAudioToFiles();
    });
  }
  
  Future<void> _saveRecentAudioToFiles() async {
    if (_completeProcessedAudio.isEmpty || _completeOriginalAudio.isEmpty) {
      return;
    }
    
    try {
      final processedAudio = _mergeAudioFrames(_completeProcessedAudio);
      final originalAudio = _mergeAudioFrames(_completeOriginalAudio);
      
      await _saveAudioAsWav(processedAudio, _realtimeProcessedPath);
      await _saveAudioAsWav(originalAudio, _realtimeOriginalPath);
      
      print('定期保存完成 - 当前音频长度: ${originalAudio.length}样本 (${(originalAudio.length / SAMPLE_RATE).toStringAsFixed(1)}秒)');
      
    } catch (e) {
      print('保存音频文件失败: $e');
    }
  }
  
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
  
  Future<void> _saveAudioAsWav(Float32List audioData, String filePath) async {
    try {
      print('开始保存WAV文件: $filePath');
      
      final file = File(filePath);
      final int16Data = Int16List(audioData.length);
      for (int i = 0; i < audioData.length; i++) {
        int16Data[i] = (audioData[i] * 32767).clamp(-32768, 32767).round();
      }
      
      final sampleRate = SAMPLE_RATE;
      final numChannels = 1;
      final bitsPerSample = 16;
      final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
      final blockAlign = numChannels * bitsPerSample ~/ 8;
      final dataSize = int16Data.length * 2;
      final fileSize = 36 + dataSize;
      
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
      
      final bytes = <int>[];
      bytes.addAll(header.buffer.asUint8List());
      bytes.addAll(int16Data.buffer.asUint8List());
      
      await file.writeAsBytes(bytes);
      
    } catch (e) {
      print('保存WAV文件失败: $e');
      throw Exception('保存WAV文件失败: $e');
    }
  }
  
  Future<void> _playAudio(String audioPath, String messagePrefix) async {
    print('准备播放音频: $audioPath');

    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      onError?.call('音频文件不存在，请等待或重新生成');
      return;
    }

    try {
      _currentPlayingFilePath = audioPath;
      await _player.setAudioSource(AudioSource.uri(Uri.file(audioPath)));
      await _player.play();
      onStatusChanged?.call('$messagePrefix 开始播放');
      Fluttertoast.showToast(msg: '$messagePrefix 开始播放');
    } catch (e) {
      print('播放失败: $e');
      onError?.call('播放失败: $e');
      _currentPlayingFilePath = null;
      if (_isPlayingStream && audioPath.contains("realtime")) _isPlayingStream = false;
      if (_isPlayingFile && audioPath.contains("selected")) _isPlayingFile = false;

      onStateChanged?.call();
    }
  }
  
  double _calculateRMS(Float32List audioData) {
    if (audioData.isEmpty) return 0.0;
    
    double sum = 0.0;
    for (int i = 0; i < audioData.length; i++) {
      sum += audioData[i] * audioData[i];
    }
    return math.sqrt(sum / audioData.length);
  }
  
  void _analyzeAudioDifference() {
    if (_completeOriginalAudio.isEmpty || _completeProcessedAudio.isEmpty) {
      return;
    }
    
    final originalMerged = _mergeAudioFrames(_completeOriginalAudio);
    final processedMerged = _mergeAudioFrames(_completeProcessedAudio);
    
    final originalRMS = _calculateRMS(originalMerged);
    final processedRMS = _calculateRMS(processedMerged);
    final rmsRatio = processedRMS / originalRMS;
    
    print('=== 音频处理分析报告 ===');
    print('原始音频RMS: ${originalRMS.toStringAsFixed(6)}');
    print('处理后音频RMS: ${processedRMS.toStringAsFixed(6)}');
    print('RMS比值: ${rmsRatio.toStringAsFixed(3)} (1.0表示无变化)');
  }
  
  Future<void> selectAudioFileAndPreparePaths(String filePath) async {
    if (!_isInitialized) {
      onError?.call('音频管理器未初始化');
      return;
    }

    onStatusChanged?.call('选择音频文件: ${path_helper.basename(filePath)}');
    
    _selectedAudioFilePath = filePath;
    final fileName = path_helper.basenameWithoutExtension(filePath);

    _selectedOriginalWavPath = path_helper.join(_appDir, '${fileName}_original_copy.wav');
    _selectedProcessedWavPath = path_helper.join(_appDir, '${fileName}_processed_full.wav');

    try {
      final originalFile = File(filePath);
      if (!await originalFile.exists()) {
        throw Exception("选择的文件不存在: $filePath");
      }

      if (_isPlayingFile) {
        _isExpectedPlayerStop = true;
        await _player.stop();
        _isPlayingFile = false;
        _currentPlayingFilePath = null;
      }
      
      await originalFile.copy(_selectedOriginalWavPath!);
      print('原始文件已复制到: $_selectedOriginalWavPath');
      
      final processedFullFile = File(_selectedProcessedWavPath!);
      if (await processedFullFile.exists()) {
        await processedFullFile.delete();
        print('旧的处理后文件已删除: $_selectedProcessedWavPath');
      }

      _completeOriginalAudio.clear();
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
      _isExpectedPlayerStop = true;
      await _stopAndCleanupFileProcessing();
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
      String pathToPlay = _isDenoisingEnabledForStream ? _realtimeProcessedPath : _realtimeOriginalPath;
      String messagePrefix = _isDenoisingEnabledForStream ? '实时降噪音频' : '实时原始音频';
      
      if (!await File(pathToPlay).exists()) {
        onError?.call('$messagePrefix 文件不存在，请先录制。'); return;
      }
      
      if (_currentPlayingFilePath == pathToPlay && _player.processingState != ProcessingState.completed) {
        await _player.play();
      } else {
        await _playAudio(pathToPlay, messagePrefix);
      }
      _isPlayingStream = true;
    }
    onStateChanged?.call();
  }

  Future<void> _stopAndCleanupFileProcessing() async {
    _stopFileChunkProcessingLoop = true;
    if (_isChunkProcessingActive || _isPlayingFile) {
        _isExpectedPlayerStop = true;
        await _player.stop();
    }
    _isPlayingFile = false;
    _isFileProcessing = false;
    _isChunkProcessingActive = false;
    _currentPlayingFilePath = null;
    
    _concatenatingFileSource = null;
    _cleanupChunkFiles();
    onStateChanged?.call();
  }

  void _cleanupChunkFiles() {
      for (String p in _processedChunkFilePaths) { 
        try { File(p).deleteSync();} catch(e){print("Error deleting chunk $p: $e");} 
      }
      _processedChunkFilePaths.clear();
      
      if (_currentTempFilePath != null) {
        try { 
          File(_currentTempFilePath!).deleteSync();
        } catch(e) {
          print("Error deleting current temp file $_currentTempFilePath: $e");
        }
        _currentTempFilePath = null;
      }
      
      _audioBufferQueue.clear();
      _bufferPlaybackIndex = 0;
      print("_cleanupChunkFiles: Cleared chunk files and buffer queue.");
  }

  Future<void> toggleFilePlayback() async {
    if (_isPlayingStream) {
        _isExpectedPlayerStop = true;
        await _player.stop(); _isPlayingStream = false; _currentPlayingFilePath = null;
        onStatusChanged?.call('已停止实时流播放以播放文件');
    }

    if (_selectedOriginalWavPath == null) {
      onError?.call('请先选择一个音频文件');
      return;
    }

    if (_isPlayingFile) {
      if (_isDenoisingEnabledForFile) {
        _stopFileChunkProcessingLoop = true; 
      }
      _isExpectedPlayerStop = true;
      await _player.pause();
      _isPlayingFile = false; 
      _isFileProcessing = false;
      onStatusChanged?.call('文件音频暂停');
    } else {
      if (_isDenoisingEnabledForFile) {
        onStatusChanged?.call('文件降噪音频 (分块流式) 准备中...');
        
        if (_currentPlayingFilePath != _selectedOriginalWavPath || !_player.playing) {
             if(_player.playing) {
                _isExpectedPlayerStop = true;
                await _player.stop();
             }
             _cleanupChunkFiles();
             
             if (_useMemoryStreamPlayback) {
                print("Preparing for memory stream playback.");
             } else {
                _concatenatingFileSource = ConcatenatingAudioSource(children: [], useLazyPreparation: true);
                try {
                   await _player.setAudioSource(_concatenatingFileSource!, initialIndex: 0, preload: true);
                } catch (e) {
                   onError?.call("播放器设置失败: $e");
                   _isFileProcessing = false;
                   onStateChanged?.call();
                   return;
                }
             }
        }
        _currentPlayingFilePath = _selectedOriginalWavPath;
        
        try {
            _isPlayingFile = true;
            _isFileProcessing = true;
            
             if (_useMemoryStreamPlayback) {
                _processAndFeedFileChunks();
             } else {
                await _player.play();
                _processAndFeedFileChunks();
             }
            
        } catch (e) {
            onError?.call("播放器启动失败: $e");
            _isPlayingFile = false;
            _isFileProcessing = false;
            await _stopAndCleanupFileProcessing(); 
            return;
        }
      } else {
        onStatusChanged?.call('文件原始音频准备中...');
        await _stopAndCleanupFileProcessing();

        try {
            if (_currentPlayingFilePath == _selectedOriginalWavPath && 
                _player.processingState != ProcessingState.completed &&
                !_player.playing &&
                _player.audioSource != null) {
               await _player.play(); 
            } else {
               _currentPlayingFilePath = _selectedOriginalWavPath;
               await _player.setAudioSource(AudioSource.uri(Uri.file(_selectedOriginalWavPath!)));
               await _player.play();
               onStatusChanged?.call('文件原始音频 开始播放');
            }
            _isPlayingFile = true;
        } catch (e) {
            onError?.call('播放原始文件失败: $e');
            _isPlayingFile = false;
            _currentPlayingFilePath = null; 
        }
      }
    }
    onStateChanged?.call();
  }
  
  Future<void> _processAndFeedFileChunks() async {
    if (_selectedOriginalWavPath == null || !_isPlayingFile) { 
      _isChunkProcessingActive = false;
      _isFileProcessing = false;
       onStateChanged?.call();
      return;
    }

    _isChunkProcessingActive = true;
    _isFileProcessing = true; 
    _stopFileChunkProcessingLoop = false;
    _audioBufferQueue.clear();
    _bufferPlaybackIndex = 0;
    onStateChanged?.call(); 

    RandomAccessFile? raf;
    int chunkIndex = 0;
    _completeOriginalAudio.clear(); 
    _completeProcessedAudio.clear();
    int totalAudioBytes = 0;
    
    int dataStartPosition = 44; 
    int originalSampleRate = 48000;
    int numChannels = 1;
    int bitsPerSample = 16;

    try {
      raf = await File(_selectedOriginalWavPath!).open(mode: FileMode.read);
      
      if (await raf.length() >= 44) {
          final headerCheckBytes = await raf.read(math.min(200, await raf.length())); 
          await raf.setPosition(0); 

          if (String.fromCharCodes(headerCheckBytes.sublist(0,4)) != "RIFF" || 
              String.fromCharCodes(headerCheckBytes.sublist(8,12)) != "WAVE") {
              throw Exception("Selected file is not a valid WAV file.");
          }

          final headerBytes = ByteData.view(headerCheckBytes.buffer, headerCheckBytes.offsetInBytes, headerCheckBytes.length);
          
          numChannels = headerBytes.getUint16(22, Endian.little);
          originalSampleRate = headerBytes.getUint32(24, Endian.little);
          bitsPerSample = headerBytes.getUint16(34, Endian.little);
          
          print('--- WAV Header Info (Chunk Processing) ---');
          print('Sample Rate: ${originalSampleRate}Hz, Channels: $numChannels, BitsPerSample: ${bitsPerSample}bit');
          
          if (originalSampleRate != SAMPLE_RATE) {
            print('⚠️ Sample rate mismatch: File is ${originalSampleRate}Hz, RNNoise requires ${SAMPLE_RATE}Hz. This may affect pitch.');
          }
        
          int searchPos = 12;
          bool foundData = false;
          while(searchPos < headerCheckBytes.length - 8) {
              String chunkId = String.fromCharCodes(headerCheckBytes.sublist(searchPos, searchPos + 4));
              if (searchPos + 8 > headerCheckBytes.length) break; 
              int chunkSize = ByteData.view(headerCheckBytes.buffer, headerCheckBytes.offsetInBytes + searchPos + 4, 4).getUint32(0, Endian.little);
              
              if (chunkId == 'data') {
                  dataStartPosition = searchPos + 8;
                  foundData = true;
                  break;
              }
              searchPos += (8 + chunkSize);
              if (chunkSize % 2 != 0 && searchPos < headerCheckBytes.length) searchPos++; 
          }
          if (!foundData) {
             throw Exception("Could not find 'data' chunk in WAV.");
          }
      } else {
        throw Exception("File too short to be a valid WAV.");
      }
    
      await raf.setPosition(dataStartPosition);
      totalAudioBytes = await raf.length() - dataStartPosition;
      
      int samplesPerChunk = SAMPLE_RATE * _chunkDurationSeconds;
      int bytesPerChunkTarget = samplesPerChunk * (bitsPerSample ~/ 8) * numChannels;

      while (totalAudioBytes > 0 && !_stopFileChunkProcessingLoop && _isPlayingFile) {
        onStatusChanged?.call("Processing chunk ${chunkIndex + 1}...");

        while (_audioBufferQueue.length >= _maxBufferQueueSize && !_stopFileChunkProcessingLoop && _isPlayingFile) {
          await Future.delayed(Duration(milliseconds: 200));
        }

        if (_stopFileChunkProcessingLoop || !_isPlayingFile) break;

        int bytesToRead = math.min(bytesPerChunkTarget, totalAudioBytes);
        if (bytesToRead <= 0) break;
        
        Uint8List pcmChunkBytes = await raf.read(bytesToRead);
        if (pcmChunkBytes.isEmpty) break;

        if (numChannels > 1) {
            pcmChunkBytes = _downmixToMono(pcmChunkBytes, bitsPerSample, numChannels);
        }
        
        totalAudioBytes -= bytesToRead;

        final processedChunk = await _processAudioChunk(pcmChunkBytes, chunkIndex);
        
        if (processedChunk != null && !_stopFileChunkProcessingLoop && _isPlayingFile) {
          final wavData = _createWavFromPCM(processedChunk, SAMPLE_RATE, 1, 16);
          _audioBufferQueue.add(wavData);
          
          if (chunkIndex == 0) {
            _startBufferedPlayback();
          }
        }
        
        chunkIndex++;
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      onStatusChanged?.call("Chunk processing complete. Total chunks: $chunkIndex");
    
    } catch (e, s) {
      onError?.call("Failed to process audio chunks: $e");
      print("Error in _processAndFeedFileChunks: $e\nStackTrace: $s");
    } finally {
      await raf?.close();
      _isChunkProcessingActive = false;
      if (_stopFileChunkProcessingLoop || !_isPlayingFile) {
          _isFileProcessing = false;
      }
      onStateChanged?.call();
    }
  }

  Uint8List _downmixToMono(Uint8List multiChannelPcm, int bitsPerSample, int numChannels) {
      if (numChannels <= 1) return multiChannelPcm;
      if (bitsPerSample != 16) {
          print("Warning: Only 16-bit audio is supported for downmixing. Skipping.");
          return multiChannelPcm;
      }

      int bytesPerSample = bitsPerSample ~/ 8;
      int frameSize = bytesPerSample * numChannels;
      int frameCount = multiChannelPcm.lengthInBytes ~/ frameSize;
      
      final monoPcm = Uint8List(frameCount * bytesPerSample);
      final multiChannelView = ByteData.view(multiChannelPcm.buffer, multiChannelPcm.offsetInBytes, multiChannelPcm.lengthInBytes);
      final monoView = ByteData.view(monoPcm.buffer);

      for (int i = 0; i < frameCount; i++) {
          int frameOffset = i * frameSize;
          int sum = 0;
          for (int c = 0; c < numChannels; c++) {
              sum += multiChannelView.getInt16(frameOffset + c * bytesPerSample, Endian.little);
          }
          int avgSample = (sum / numChannels).round();
          monoView.setInt16(i * bytesPerSample, avgSample, Endian.little);
      }
      
      return monoPcm;
  }

  Future<Uint8List?> _processAudioChunk(Uint8List pcmChunkBytes, int chunkIndex) async {
    try {
      List<Float32List> originalFramesInChunk = [];
      List<Float32List> processedFramesInChunk = [];
      
      ByteData pcmChunkByteData = ByteData.view(pcmChunkBytes.buffer, pcmChunkBytes.offsetInBytes, pcmChunkBytes.lengthInBytes);
      int currentByteOffset = 0;

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
        Float32List processedChunkF32 = _mergeAudioFrames(processedFramesInChunk);
        _completeOriginalAudio.addAll(originalFramesInChunk); 
        _completeProcessedAudio.addAll(processedFramesInChunk);
        
        final pcmData = Uint8List(processedChunkF32.length * 2);
        final pcmByteData = ByteData.view(pcmData.buffer);
        for (int i = 0; i < processedChunkF32.length; i++) {
          int sample = (processedChunkF32[i] * 32767).round().clamp(-32768, 32767);
          pcmByteData.setInt16(i * 2, sample, Endian.little);
        }
        
        return pcmData;
      }
      
      return null;
    } catch (e) {
      print("Error processing audio chunk $chunkIndex: $e");
      return null;
    }
  }

  Uint8List _createWavFromPCM(Uint8List pcmData, int sampleRate, int channels, int bitsPerSample) {
    final dataSize = pcmData.length;
    final totalSize = 44 + dataSize;
    
    final wavData = Uint8List(totalSize);
    final wavView = ByteData.view(wavData.buffer);
    
    wavData.setRange(0, 4, 'RIFF'.codeUnits);
    wavView.setUint32(4, totalSize - 8, Endian.little);
    wavData.setRange(8, 12, 'WAVE'.codeUnits);
    
    wavData.setRange(12, 16, 'fmt '.codeUnits);
    wavView.setUint32(16, 16, Endian.little);
    wavView.setUint16(20, 1, Endian.little);
    wavView.setUint16(22, channels, Endian.little);
    wavView.setUint32(24, sampleRate, Endian.little);
    wavView.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
    wavView.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    wavView.setUint16(34, bitsPerSample, Endian.little);
    
    wavData.setRange(36, 40, 'data'.codeUnits);
    wavView.setUint32(40, dataSize, Endian.little);
    wavData.setRange(44, 44 + dataSize, pcmData);
    
    return wavData;
  }

  void _startBufferedPlayback() async {
    if (_audioBufferQueue.isEmpty) return;
    
    _consumeAudioBuffers();
  }

  void _consumeAudioBuffers() async {
    if (_useMemoryStreamPlayback) {
      _consumeAudioBuffersMemoryStream();
    } else {
      _consumeAudioBuffersFileMode();
    }
  }

  void _consumeAudioBuffersMemoryStream() async {
    Uint8List? completeAudioData;
    bool hasStartedPlayback = false;
    int chunksProcessedSinceLastUpdate = 0;
    const int initialBatchSize = 3;
    const int updateBatchSize = 2;
    Duration lastPlayPosition = Duration.zero;
    
    while (_isPlayingFile && !_stopFileChunkProcessingLoop) {
      if (_audioBufferQueue.isNotEmpty) {
        final audioData = _audioBufferQueue.removeFirst();
        
        try {
          if (!hasStartedPlayback) {
            completeAudioData = audioData;
            int initialBatchCount = 1;
            
            while (initialBatchCount < initialBatchSize) {
              while (_audioBufferQueue.isEmpty && _isChunkProcessingActive) {
                await Future.delayed(Duration(milliseconds: 50));
              }
              
              if (_audioBufferQueue.isNotEmpty) {
                final nextChunk = _audioBufferQueue.removeFirst();
                completeAudioData = _appendWavChunks(completeAudioData!, nextChunk);
                initialBatchCount++;
              } else if (!_isChunkProcessingActive) {
                break;
              }
            }
            
            await _startProgressivePlayback(completeAudioData!);
            hasStartedPlayback = true;
            chunksProcessedSinceLastUpdate = 0;
          } else {
            completeAudioData = _appendWavChunks(completeAudioData!, audioData);
            chunksProcessedSinceLastUpdate++;
            
            if (chunksProcessedSinceLastUpdate >= updateBatchSize || 
                (_audioBufferQueue.isEmpty && !_isChunkProcessingActive)) {
              
              await _updateProgressivePlayback(completeAudioData, lastPlayPosition);
              chunksProcessedSinceLastUpdate = 0;
            }
          }
          
          if (_player.duration != null && _player.position.inMilliseconds > 0) {
            lastPlayPosition = _player.position;
          }
          
          await Future.delayed(Duration(milliseconds: 30));
        } catch (e) {
          print("Error in progressive playback: $e");
        }
      } else {
        if (!_isChunkProcessingActive && hasStartedPlayback && chunksProcessedSinceLastUpdate > 0) {
          await _updateProgressivePlayback(completeAudioData!, lastPlayPosition);
          break;
        }
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
    
    if (hasStartedPlayback && _player.duration != null && completeAudioData != null) {
      final finalDuration = _player.duration!.inMilliseconds / 1000.0;
      final finalDataSize = completeAudioData.length - 44;
      final expectedFinalDuration = finalDataSize / (SAMPLE_RATE * 1 * 2);
      print('--- Final Playback Analysis ---');
      print('Final PCM Size: ${finalDataSize} bytes');
      print('Expected Duration: ${expectedFinalDuration.toStringAsFixed(2)}s');
      print('Actual Player Duration: ${finalDuration.toStringAsFixed(2)}s');
      print('Ratio (Actual/Expected): ${(finalDuration / expectedFinalDuration).toStringAsFixed(3)}');
    }
  }
  
  Uint8List _appendWavChunks(Uint8List baseWav, Uint8List newWav) {
    final basePcm = baseWav.sublist(44);
    final newPcm = newWav.sublist(44);

    final combinedPcm = Uint8List(basePcm.length + newPcm.length);
    combinedPcm.setRange(0, basePcm.length, basePcm);
    combinedPcm.setRange(basePcm.length, combinedPcm.length, newPcm);

    return _createWavFromPCM(combinedPcm, SAMPLE_RATE, 1, 16);
  }

  Future<void> _startProgressivePlayback(Uint8List initialAudioData) async {
    try {
      final base64Audio = base64Encode(initialAudioData);
      final dataUri = 'data:audio/wav;base64,$base64Audio';
      
      await _player.setAudioSource(AudioSource.uri(Uri.parse(dataUri)));
      await _player.play();
      
    } catch (e) {
      onError?.call("Failed to start progressive playback: $e");
    }
  }
  
  Future<void> _updateProgressivePlayback(Uint8List updatedAudioData, Duration lastPosition) async {
    try {
      final wasPlaying = _player.playing;
      final currentPosition = _player.position;
      
      final base64Audio = base64Encode(updatedAudioData);
      final dataUri = 'data:audio/wav;base64,$base64Audio';
      
      await _player.setAudioSource(AudioSource.uri(Uri.parse(dataUri)));
      
      if (currentPosition.inMilliseconds > 0) {
        await _player.seek(currentPosition);
      }
      
      if (wasPlaying) {
        await _player.play();
      }
      
    } catch (e) {
      print("Error updating progressive playback: $e");
    }
  }

  void _consumeAudioBuffersFileMode() async {
    while (_isPlayingFile && !_stopFileChunkProcessingLoop) {
      if (_audioBufferQueue.isNotEmpty) {
        final audioData = _audioBufferQueue.removeFirst();
        
        final tempFile = File(path_helper.join(_appDir, "temp_chunk_${DateTime.now().millisecondsSinceEpoch}.wav"));
        await tempFile.writeAsBytes(audioData);
        
        try {
          if (_concatenatingFileSource != null && _isPlayingFile) {
            await _concatenatingFileSource!.add(AudioSource.uri(Uri.file(tempFile.path)));
            _bufferPlaybackIndex++;
            
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
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
  }

  Future<void> dispose() async {
    try {
      if (_isStreamProcessing) {
        await stopStreamProcessing();
      }
      if (_isRecording) {
        await stopRecording();
      }
      
      await _stopAndCleanupFileProcessing();
      _rnnoise.cleanupState();
      _audioSaveTimer?.cancel();
      _audioReadTimer?.cancel();
      await _audioDataSubscription?.cancel();
      await _audioStreamController?.close();
      await _player.dispose();
      await _recorder.dispose();
      _streamProcessor?.dispose();
      
      _isInitialized = false;
      
    } catch (e) {
      print('释放资源时出错: $e');
    }
  }
} 

class AudioProcessResult {
  final Float32List processedAudio;
  final double vadProbability;
  final int framesProcessed;
  final DateTime timestamp;

  AudioProcessResult({
    required this.processedAudio,
    required this.vadProbability,
    required this.framesProcessed,
    required this.timestamp,
  });
}







