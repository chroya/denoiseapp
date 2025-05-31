import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'rnnoise_ffi.dart';

/// 音频流处理器
/// 
/// 实现多帧批处理的流式音频降噪
class AudioStreamProcessor {
  static const int FRAME_SIZE = 480; // 每帧样本数 (10ms at 48kHz)
  static const int DEFAULT_FRAMES_PER_BATCH = 4; // 默认每批处理4帧
  static const int MAX_BUFFER_SIZE = FRAME_SIZE * 16; // 最大缓冲区大小
  
  final RNNoiseFFI _rnnoise = RNNoiseFFI();
  final int _framesPerBatch;
  final int _batchSize;
  
  // 音频帧缓冲区
  final List<double> _buffer = [];
  
  // 对象池，减少内存分配
  final Queue<Float32List> _framePool = Queue<Float32List>();
  final int _maxPoolSize = 10;
  
  // 状态管理
  bool _isInitialized = false;
  bool _isProcessing = false;
  
  // 统计信息
  int _totalFramesProcessed = 0;
  double _averageVadProbability = 0.0;
  
  AudioStreamProcessor({int framesPerBatch = DEFAULT_FRAMES_PER_BATCH})
      : _framesPerBatch = framesPerBatch,
        _batchSize = FRAME_SIZE * framesPerBatch;
  
  /// 初始化处理器
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      _isInitialized = _rnnoise.initializeState();
      return _isInitialized;
    } catch (e) {
      print('音频流处理器初始化失败: $e');
      return false;
    }
  }
  
  /// 清理资源
  void dispose() {
    if (_isInitialized) {
      _rnnoise.cleanupState();
      _isInitialized = false;
    }
    
    _buffer.clear();
    _framePool.clear();
    _isProcessing = false;
  }
  
  /// 处理音频流
  /// 
  /// [inputStream] 输入音频流
  /// 返回处理后的音频流
  Stream<AudioProcessResult> processStream(Stream<Float32List> inputStream) async* {
    if (!_isInitialized) {
      throw StateError('处理器未初始化，请先调用 initialize()');
    }
    
    _isProcessing = true;
    
    try {
      await for (var chunk in inputStream) {
        if (!_isProcessing) break;
        
        // 添加新数据到缓冲区
        _buffer.addAll(chunk);
        
        // 当缓冲区达到批处理大小时进行处理
        while (_buffer.length >= _batchSize) {
          // 提取一批数据
          final batch = _getBatchBuffer();
          for (var i = 0; i < _batchSize; i++) {
            batch[i] = _buffer[i];
          }
          _buffer.removeRange(0, _batchSize);
          
          // 处理这批数据
          final result = await _processBatch(batch);
          
          // 回收缓冲区
          _recycleBatchBuffer(batch);
          
          // 输出处理后的数据
          yield result;
        }
      }
      
      // 处理剩余数据
      if (_buffer.isNotEmpty && _isProcessing) {
        final remainingResult = await _processRemainingData();
        if (remainingResult != null) {
          yield remainingResult;
        }
      }
    } finally {
      _isProcessing = false;
    }
  }
  
  /// 停止处理
  void stop() {
    _isProcessing = false;
  }
  
  /// 获取批处理缓冲区
  Float32List _getBatchBuffer() {
    if (_framePool.isNotEmpty) {
      return _framePool.removeFirst();
    }
    return Float32List(_batchSize);
  }
  
  /// 回收批处理缓冲区
  void _recycleBatchBuffer(Float32List buffer) {
    if (_framePool.length < _maxPoolSize) {
      _framePool.add(buffer);
    }
  }
  
  /// 处理一批数据
  Future<AudioProcessResult> _processBatch(Float32List batch) async {
    try {
      final result = _rnnoise.processFrames(batch, _framesPerBatch);
      
      // 更新统计信息
      _totalFramesProcessed += _framesPerBatch;
      _averageVadProbability = (_averageVadProbability * (_totalFramesProcessed - _framesPerBatch) + 
                               result.vadProbability * _framesPerBatch) / _totalFramesProcessed;
      
      return AudioProcessResult(
        processedAudio: result.processedAudio,
        vadProbability: result.vadProbability,
        framesProcessed: _framesPerBatch,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      throw AudioProcessingException('批处理失败: $e');
    }
  }
  
  /// 处理剩余数据
  Future<AudioProcessResult?> _processRemainingData() async {
    if (_buffer.isEmpty) return null;
    
    // 计算需要处理的完整帧数
    final completeFrames = _buffer.length ~/ FRAME_SIZE;
    if (completeFrames == 0) return null;
    
    // 用0填充到批处理大小
    final paddedSize = completeFrames * FRAME_SIZE;
    final batch = _getBatchBuffer();
    
    for (var i = 0; i < paddedSize; i++) {
      batch[i] = _buffer[i];
    }
    
    // 用0填充剩余部分
    for (var i = paddedSize; i < _batchSize; i++) {
      batch[i] = 0.0;
    }
    
    try {
      final result = _rnnoise.processFrames(batch, _framesPerBatch);
      
      // 只返回有效的音频数据
      final validAudio = Float32List(paddedSize);
      for (var i = 0; i < paddedSize; i++) {
        validAudio[i] = result.processedAudio[i];
      }
      
      _recycleBatchBuffer(batch);
      _buffer.clear();
      
      return AudioProcessResult(
        processedAudio: validAudio,
        vadProbability: result.vadProbability,
        framesProcessed: completeFrames,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      _recycleBatchBuffer(batch);
      throw AudioProcessingException('处理剩余数据失败: $e');
    }
  }
  
  /// 获取统计信息
  AudioProcessorStats get stats => AudioProcessorStats(
    totalFramesProcessed: _totalFramesProcessed,
    averageVadProbability: _averageVadProbability,
    isProcessing: _isProcessing,
    bufferSize: _buffer.length,
    poolSize: _framePool.length,
  );
  
  /// 手动更新统计信息（用于模拟处理）
  void updateStats(int framesProcessed, double vadProbability) {
    _totalFramesProcessed += framesProcessed;
    _averageVadProbability = vadProbability;
  }
}

/// 音频处理结果
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
  
  /// 是否检测到语音
  bool get hasVoiceActivity => vadProbability > 0.5;
  
  /// 音频长度（毫秒）
  double get durationMs => (processedAudio.length / 48000) * 1000;
}

/// 处理器统计信息
class AudioProcessorStats {
  final int totalFramesProcessed;
  final double averageVadProbability;
  final bool isProcessing;
  final int bufferSize;
  final int poolSize;
  
  AudioProcessorStats({
    required this.totalFramesProcessed,
    required this.averageVadProbability,
    required this.isProcessing,
    required this.bufferSize,
    required this.poolSize,
  });
  
  // 默认构造函数
  AudioProcessorStats.empty()
      : totalFramesProcessed = 0,
        averageVadProbability = 0.0,
        isProcessing = false,
        bufferSize = 0,
        poolSize = 0;
  
  /// 总处理时长（毫秒）
  double get totalProcessedDurationMs => (totalFramesProcessed * 480 / 48000) * 1000;
}

/// 音频处理异常
class AudioProcessingException implements Exception {
  final String message;
  
  AudioProcessingException(this.message);
  
  @override
  String toString() => 'AudioProcessingException: $message';
} 