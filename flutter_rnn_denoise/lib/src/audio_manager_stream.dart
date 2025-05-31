import 'dart:async';
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
  final AudioPlayer _originalPlayer = AudioPlayer();
  final AudioPlayer _processedPlayer = AudioPlayer();
  
  // RNNoise接口和流处理器
  final RNNoiseFFI _rnnoise = RNNoiseFFI();
  AudioStreamProcessor? _streamProcessor;
  
  // 状态
  bool _isInitialized = false;
  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isStreamProcessing = false;
  
  // 文件路径
  late String _appDir;
  late String _recordingPath;
  late String _processedPath;
  late String _realtimeProcessedPath;
  late String _realtimeOriginalPath;
  
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
  bool get isPlaying => _isPlaying;
  bool get isStreamProcessing => _isStreamProcessing;
  
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
    _processedPath = path_helper.join(_appDir, 'processed.wav');
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
    // 初始化两个播放器用于原始音频和处理后音频
    await _originalPlayer.setVolume(1.0);
    await _processedPlayer.setVolume(1.0);
    _isPlayerInitialized = true;
    print('just_audio播放器初始化完成');
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
      
      _isStreamProcessing = false;
      _isRecording = false;
      
      // 保存最终的音频文件
      await _saveFinalAudioFiles();
      
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
      
    } catch (e) {
      throw Exception('保存WAV文件失败: $e');
    }
  }
  
  /// 播放实时原始音频
  Future<void> playRealtimeOriginal() async {
    await _playRealtimeAudio(_realtimeOriginalPath, _originalPlayer, '播放原始音频');
  }
  
  /// 播放实时降噪音频
  Future<void> playRealtimeProcessed() async {
    await _playRealtimeAudio(_realtimeProcessedPath, _processedPlayer, '播放降噪音频');
  }
  
  /// 播放实时音频的通用方法
  Future<void> _playRealtimeAudio(String audioPath, AudioPlayer player, String message) async {
    if (!_isPlayerInitialized) {
      return;
    }
    
    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      onError?.call('音频文件不存在，请等待音频数据积累');
      return;
    }
    
    try {
      if (player.playing) {
        await player.stop();
        _isPlaying = false;
        onStatusChanged?.call('停止播放');
        return;
      }
      
      await player.setFilePath(audioPath);
      await player.play();
      _isPlaying = true;
      
      onStatusChanged?.call(message);
      Fluttertoast.showToast(msg: message);
      
      // 监听播放完成
      player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          onStatusChanged?.call('播放完成');
        }
      });
      
    } catch (e) {
      onError?.call('播放失败: $e');
      throw Exception('播放失败: $e');
    }
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
      await _originalPlayer.dispose();
      await _processedPlayer.dispose();
      
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






