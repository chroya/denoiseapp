import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

/// RNNoise库的FFI包装类
class RNNoiseFFI {
  static const int FRAME_SIZE = 480; // 10ms at 48kHz
  
  /// 动态库句柄
  DynamicLibrary? _lib;
  
  /// 原有的文件处理函数
  late final int Function(Pointer<Utf8>, Pointer<Utf8>) _rnnoise;
  
  /// 新增的流式处理函数
  late final int Function() _initState;
  late final void Function() _cleanupState;
  late final double Function(Pointer<Float>, Pointer<Float>, int) _processFrames;
  
  /// 单例实例
  static final RNNoiseFFI _instance = RNNoiseFFI._internal();
  
  /// 工厂构造函数
  factory RNNoiseFFI() {
    return _instance;
  }
  
  /// 私有构造函数，初始化库
  RNNoiseFFI._internal() {
    _loadLibrary();
  }
  
  /// 检查库是否已加载
  bool get isLibraryLoaded => _lib != null;
  
  /// 加载动态库
  void _loadLibrary() {
    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libdenoise.so');
      } else if (Platform.isIOS) {
        _lib = DynamicLibrary.process();
      } else {
        throw UnsupportedError('当前平台不支持RNNoise');
      }
      
      _bindFunctions();
    } catch (e) {
      print('加载RNNoise库失败: $e');
      _lib = null;
      rethrow;
    }
  }
  
  /// 绑定C函数
  void _bindFunctions() {
    if (_lib == null) {
      throw StateError('动态库未加载');
    }
    
    try {
      // 绑定原有函数
      _rnnoise = _lib!
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>)>>('rnnoise')
          .asFunction();
      
      // 绑定新的流式处理函数
      _initState = _lib!
          .lookup<NativeFunction<Int32 Function()>>('rnnoise_init_state')
          .asFunction();
      
      _cleanupState = _lib!
          .lookup<NativeFunction<Void Function()>>('rnnoise_cleanup_state')
          .asFunction();
      
      _processFrames = _lib!
          .lookup<NativeFunction<Float Function(Pointer<Float>, Pointer<Float>, Int32)>>('rnnoise_process_frames')
          .asFunction();
      
      print('所有RNNoise函数绑定成功');
    } catch (e) {
      throw Exception('绑定RNNoise函数失败: $e');
    }
  }
  
  /// 初始化降噪状态
  bool initializeState() {
    if (!isLibraryLoaded) {
      print('错误: 动态库未加载');
      return false;
    }
    
    try {
      final result = _initState();
      print('RNNoise状态初始化${result == 0 ? "成功" : "失败"} (返回值: $result)');
      return result == 0;
    } catch (e) {
      print('初始化降噪状态失败: $e');
      return false;
    }
  }
  
  /// 清理降噪状态
  void cleanupState() {
    if (!isLibraryLoaded) {
      return;
    }
    
    try {
      _cleanupState();
      print('RNNoise状态清理完成');
    } catch (e) {
      print('清理降噪状态时出错: $e');
    }
  }
  
  /// 处理多帧音频数据（核心流式处理函数）
  ProcessResult processFrames(Float32List inputFrames, int numFrames) {
    if (!isLibraryLoaded) {
      throw StateError('动态库未加载');
    }
    
    final expectedLength = FRAME_SIZE * numFrames;
    if (inputFrames.length != expectedLength) {
      throw ArgumentError('输入数据长度不匹配: 期望 $expectedLength, 实际 ${inputFrames.length}');
    }
    
    if (numFrames <= 0) {
      throw ArgumentError('帧数必须大于0: $numFrames');
    }
    
    final inputPtr = calloc<Float>(expectedLength);
    final outputPtr = calloc<Float>(expectedLength);
    
    try {
      // 复制输入数据到本地内存
      for (var i = 0; i < expectedLength; i++) {
        inputPtr[i] = inputFrames[i];
      }
      
      // 处理音频帧
      final vadProb = _processFrames(outputPtr, inputPtr, numFrames);
      
      // 检查返回值
      if (vadProb < 0) {
        throw Exception('音频处理失败，返回值: $vadProb');
      }
      
      // 创建输出缓冲区
      final output = Float32List(expectedLength);
      for (var i = 0; i < expectedLength; i++) {
        output[i] = outputPtr[i];
      }
      
      return ProcessResult(output, vadProb);
    } catch (e) {
      throw Exception('处理音频帧时出错: $e');
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }
  
  /// 处理音频文件（保持向后兼容）
  int processAudioFile(String inputPath, String outputPath) {
    if (!isLibraryLoaded) {
      throw StateError('动态库未加载');
    }
    
    final inputPathPointer = inputPath.toNativeUtf8();
    final outputPathPointer = outputPath.toNativeUtf8();
    
    try {
      final result = _rnnoise(inputPathPointer, outputPathPointer);
      print('音频文件处理${result == 0 ? "成功" : "失败"} (返回值: $result)');
      return result;
    } catch (e) {
      throw Exception('处理音频文件时出错: $e');
    } finally {
      // 释放内存
      calloc.free(inputPathPointer);
      calloc.free(outputPathPointer);
    }
  }
}

/// 处理结果类
class ProcessResult {
  final Float32List processedAudio;
  final double vadProbability;
  
  ProcessResult(this.processedAudio, this.vadProbability);
  
  @override
  String toString() {
    return 'ProcessResult(audioLength: ${processedAudio.length}, vadProb: ${vadProbability.toStringAsFixed(3)})';
  }
} 