import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

/// RNNoise库的FFI包装类
class RNNoiseFFI {
  /// 动态库句柄
  late final DynamicLibrary _lib;
  
  /// RNNoise处理函数的类型定义
  late final int Function(Pointer<Utf8>, Pointer<Utf8>) _rnnoise;
  
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
      
      // 查找并绑定rnnoise函数
      _rnnoise = _lib
          .lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>)>>('rnnoise')
          .asFunction();
    } catch (e) {
      throw Exception('加载RNNoise库失败: $e');
    }
  }
  
  /// 处理音频文件
  /// 
  /// [inputPath] 输入音频文件路径
  /// [outputPath] 输出音频文件路径
  /// 
  /// 返回处理结果状态码
  int processAudioFile(String inputPath, String outputPath) {
    final inputPathPointer = inputPath.toNativeUtf8();
    final outputPathPointer = outputPath.toNativeUtf8();
    
    try {
      return _rnnoise(inputPathPointer, outputPathPointer);
    } finally {
      // 释放内存
      calloc.free(inputPathPointer);
      calloc.free(outputPathPointer);
    }
  }
} 