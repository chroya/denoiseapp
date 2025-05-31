import 'dart:typed_data';
import 'rnnoise_ffi.dart';
import 'dart:async';
import 'dart:math';

/// RNNoise FFI调用测试工具
class RNNoiseTest {
  static final RNNoiseFFI _rnnoise = RNNoiseFFI();
  static final StringBuffer _output = StringBuffer();
  
  /// 添加日志到输出缓冲区
  static void _log(String message) {
    _output.writeln(message);
  }
  
  /// 清空输出缓冲区
  static void _clearOutput() {
    _output.clear();
  }
  
  /// 获取输出内容
  static String getOutput() {
    return _output.toString();
  }
  
  /// 测试库加载
  static bool testLibraryLoading() {
    _log('=== 测试动态库加载 ===');
    try {
      final isLoaded = _rnnoise.isLibraryLoaded;
      _log('库加载状态: ${isLoaded ? "成功" : "失败"}');
      return isLoaded;
    } catch (e) {
      _log('库加载测试失败: $e');
      return false;
    }
  }
  
  /// 测试状态初始化
  static bool testStateInitialization() {
    _log('\n=== 测试状态初始化 ===');
    try {
      final success = _rnnoise.initializeState();
      _log('状态初始化: ${success ? "成功" : "失败"}');
      return success;
    } catch (e) {
      _log('状态初始化测试失败: $e');
      return false;
    }
  }
  
  /// 测试单帧处理
  static bool testSingleFrameProcessing() {
    _log('\n=== 测试单帧处理 ===');
    try {
      // 创建测试数据：480个样本的正弦波
      final testData = Float32List(RNNoiseFFI.FRAME_SIZE);
      for (int i = 0; i < RNNoiseFFI.FRAME_SIZE; i++) {
        // 生成1kHz正弦波 + 噪声
        testData[i] = (32767 * 0.5 * 
            (sin(2 * 3.14159 * 1000 * i / 48000) + 
             0.1 * (2 * (i % 17) / 17 - 1))).toDouble();
      }
      
      _log('输入数据长度: ${testData.length}');
      _log('输入数据范围: ${testData.reduce((a, b) => a < b ? a : b).toStringAsFixed(2)} ~ ${testData.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)}');
      
      final result = _rnnoise.processFrames(testData, 1);
      
      _log('处理结果 - VAD概率: ${result.vadProbability.toStringAsFixed(3)}');
      _log('输出数据长度: ${result.processedAudio.length}');
      _log('输出数据范围: ${result.processedAudio.reduce((a, b) => a < b ? a : b).toStringAsFixed(2)} ~ ${result.processedAudio.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)}');
      
      // 验证结果合理性
      if (result.vadProbability >= 0 && result.vadProbability <= 1) {
        _log('VAD概率在合理范围内');
        return true;
      } else {
        _log('VAD概率超出范围: ${result.vadProbability}');
        return false;
      }
    } catch (e) {
      _log('单帧处理测试失败: $e');
      return false;
    }
  }
  
  /// 测试多帧处理
  static bool testMultiFrameProcessing() {
    _log('\n=== 测试多帧处理 ===');
    try {
      const numFrames = 4;
      final testData = Float32List(RNNoiseFFI.FRAME_SIZE * numFrames);
      
      // 生成测试数据
      for (int frame = 0; frame < numFrames; frame++) {
        for (int i = 0; i < RNNoiseFFI.FRAME_SIZE; i++) {
          final sampleIndex = frame * RNNoiseFFI.FRAME_SIZE + i;
          testData[sampleIndex] = (32767 * 0.3 * 
              sin(2 * 3.14159 * 800 * sampleIndex / 48000)).toDouble();
        }
      }
      
      _log('输入数据: ${numFrames}帧，总长度: ${testData.length}');
      
      final result = _rnnoise.processFrames(testData, numFrames);
      
      _log('处理结果 - 平均VAD概率: ${result.vadProbability.toStringAsFixed(3)}');
      _log('输出数据长度: ${result.processedAudio.length}');
      
      return result.vadProbability >= 0 && result.vadProbability <= 1;
    } catch (e) {
      _log('多帧处理测试失败: $e');
      return false;
    }
  }

  /// FFI性能压测 - 快速多次调用测试
  static bool testFFIPerformanceStress() {
    _log('\n=== FFI性能压测 ===');
    try {
      // 测试参数配置
      final testConfigs = [
        {'calls': 100, 'frames': 1, 'name': '高频单帧调用'},
        {'calls': 50, 'frames': 4, 'name': '中频多帧调用'},
        {'calls': 20, 'frames': 10, 'name': '低频大批量调用'},
        {'calls': 1000, 'frames': 1, 'name': '极限单帧调用'},
      ];

      for (final config in testConfigs) {
        final calls = config['calls'] as int;
        final frames = config['frames'] as int;
        final name = config['name'] as String;
        
        _log('\n--- $name 测试 ($calls次调用，每次$frames帧) ---');
        
        // 准备测试数据
        final testData = Float32List(RNNoiseFFI.FRAME_SIZE * frames);
        for (int i = 0; i < testData.length; i++) {
          testData[i] = (16384 * sin(2 * 3.14159 * 440 * i / 48000)).toDouble();
        }
        
        // 预热调用（避免首次调用的开销影响测试结果）
        for (int i = 0; i < 3; i++) {
          _rnnoise.processFrames(testData, frames);
        }
        
        // 开始性能测试
        final stopwatch = Stopwatch()..start();
        final List<double> vadResults = [];
        
        for (int i = 0; i < calls; i++) {
          try {
            final result = _rnnoise.processFrames(testData, frames);
            vadResults.add(result.vadProbability);
          } catch (e) {
            _log('第${i + 1}次调用失败: $e');
            return false;
          }
        }
        
        stopwatch.stop();
        
        // 计算性能指标
        final totalTimeMs = stopwatch.elapsedMicroseconds / 1000.0;
        final avgTimeMs = totalTimeMs / calls;
        final callsPerSec = (calls * 1000.0) / totalTimeMs;
        final framesPerSec = (calls * frames * 1000.0) / totalTimeMs;
        
        // 计算VAD统计
        final avgVad = vadResults.reduce((a, b) => a + b) / vadResults.length;
        final minVad = vadResults.reduce((a, b) => a < b ? a : b);
        final maxVad = vadResults.reduce((a, b) => a > b ? a : b);
        
        _log('总耗时: ${totalTimeMs.toStringAsFixed(2)}ms');
        _log('平均每次调用: ${avgTimeMs.toStringAsFixed(3)}ms');
        _log('调用频率: ${callsPerSec.toStringAsFixed(1)} calls/sec');
        _log('帧处理频率: ${framesPerSec.toStringAsFixed(1)} frames/sec');
        _log('VAD结果 - 平均: ${avgVad.toStringAsFixed(3)}, 范围: ${minVad.toStringAsFixed(3)}~${maxVad.toStringAsFixed(3)}');
        
        // 性能评估
        if (avgTimeMs < 1.0) {
          _log('🟢 性能优秀 (< 1ms/call)');
        } else if (avgTimeMs < 5.0) {
          _log('🟡 性能良好 (1-5ms/call)');
        } else {
          _log('🔴 性能需要优化 (> 5ms/call)');
        }
      }
      
      return true;
    } catch (e) {
      _log('FFI性能压测失败: $e');
      return false;
    }
  }

  /// 内存压力测试 - 测试大量数据处理时的内存使用
  static bool testMemoryStress() {
    _log('\n=== 内存压力测试 ===');
    try {
      final largeFrameCounts = [1, 5, 10, 20, 50];
      
      for (final frameCount in largeFrameCounts) {
        _log('\n--- 测试 ${frameCount}帧连续处理 ---');
        
        final dataSize = RNNoiseFFI.FRAME_SIZE * frameCount;
        final testData = Float32List(dataSize);
        
        // 生成复杂的测试信号
        for (int i = 0; i < dataSize; i++) {
          final t = i / 48000.0;
          testData[i] = (16384 * (
            sin(2 * 3.14159 * 440 * t) * 0.4 +
            sin(2 * 3.14159 * 880 * t) * 0.3 +
            sin(2 * 3.14159 * 1320 * t) * 0.2 +
            (2 * (i % 23) / 23 - 1) * 0.1  // 噪声
          )).toDouble();
        }
        
        final stopwatch = Stopwatch()..start();
        final result = _rnnoise.processFrames(testData, frameCount);
        stopwatch.stop();
        
        final processingTime = stopwatch.elapsedMicroseconds / 1000.0;
        final mbPerSec = (dataSize * 4 * 2) / (processingTime / 1000.0) / (1024 * 1024);  // 输入+输出数据量
        
        _log('数据大小: ${dataSize}样本 (${(dataSize * 4 / 1024).toStringAsFixed(1)}KB)');
        _log('处理时间: ${processingTime.toStringAsFixed(2)}ms');
        _log('数据吞吐: ${mbPerSec.toStringAsFixed(2)}MB/s');
        _log('VAD概率: ${result.vadProbability.toStringAsFixed(3)}');
        
        // 验证输出数据完整性
        if (result.processedAudio.length != dataSize) {
          _log('❌ 输出数据长度不匹配');
          return false;
        }
      }
      
      _log('\n✅ 内存压力测试完成');
      return true;
    } catch (e) {
      _log('内存压力测试失败: $e');
      return false;
    }
  }

  /// 并发调用测试 - 测试FFI的线程安全性
  static Future<bool> testConcurrentCalls() async {
    _log('\n=== 并发调用测试 ===');
    try {
      const concurrentTasks = 5;
      const callsPerTask = 20;
      
      // 准备测试数据
      final testData = Float32List(RNNoiseFFI.FRAME_SIZE);
      for (int i = 0; i < RNNoiseFFI.FRAME_SIZE; i++) {
        testData[i] = (16384 * sin(2 * 3.14159 * 660 * i / 48000)).toDouble();
      }
      
      _log('启动 $concurrentTasks 个并发任务，每个任务 $callsPerTask 次调用');
      
      final stopwatch = Stopwatch()..start();
      final futures = <Future<List<double>>>[];
      
      // 创建并发任务
      for (int task = 0; task < concurrentTasks; task++) {
        final future = Future(() async {
          final vadResults = <double>[];
          for (int call = 0; call < callsPerTask; call++) {
            final result = _rnnoise.processFrames(testData, 1);
            vadResults.add(result.vadProbability);
            
            // 添加微小延迟增加并发冲突概率
            await Future.delayed(Duration(microseconds: 100));
          }
          return vadResults;
        });
        futures.add(future);
      }
      
      // 等待所有任务完成
      final results = await Future.wait(futures);
      stopwatch.stop();
      
      // 统计结果
      int totalCalls = 0;
      double totalVad = 0;
      for (final taskResults in results) {
        totalCalls += taskResults.length;
        totalVad += taskResults.reduce((a, b) => a + b);
      }
      
      final avgVad = totalVad / totalCalls;
      final totalTime = stopwatch.elapsedMilliseconds;
      final callsPerSec = (totalCalls * 1000.0) / totalTime;
      
      _log('总调用次数: $totalCalls');
      _log('总耗时: ${totalTime}ms');
      _log('并发调用频率: ${callsPerSec.toStringAsFixed(1)} calls/sec');
      _log('平均VAD: ${avgVad.toStringAsFixed(3)}');
      _log('✅ 所有并发任务成功完成');
      
      return true;
    } catch (e) {
      _log('并发调用测试失败: $e');
      return false;
    }
  }
  
  /// 测试状态清理
  static bool testStateCleanup() {
    _log('\n=== 测试状态清理 ===');
    try {
      _rnnoise.cleanupState();
      _log('状态清理完成');
      return true;
    } catch (e) {
      _log('状态清理测试失败: $e');
      return false;
    }
  }
  
  /// 运行完整测试套件
  static Future<bool> runAllTests() async {
    _clearOutput();
    _log('🧪 RNNoise FFI调用测试开始\n');
    
    final tests = [
      ('库加载测试', () => testLibraryLoading()),
      ('状态初始化测试', () => testStateInitialization()),
      ('单帧处理测试', () => testSingleFrameProcessing()),
      ('多帧处理测试', () => testMultiFrameProcessing()),
      ('FFI性能压测', () => testFFIPerformanceStress()),
      ('内存压力测试', () => testMemoryStress()),
      ('并发调用测试', () async => await testConcurrentCalls()),
      ('状态清理测试', () => testStateCleanup()),
    ];
    
    int passed = 0;
    int total = tests.length;
    
    for (final test in tests) {
      try {
        dynamic result = test.$2();
        if (result is Future<bool>) {
          result = await result;
        }
        
        if (result == true) {
          _log('✅ ${test.$1} - 通过');
          passed++;
        } else {
          _log('❌ ${test.$1} - 失败');
        }
      } catch (e) {
        _log('❌ ${test.$1} - 异常: $e');
      }
      _log('');
    }
    
    _log('🏁 测试完成: $passed/$total 通过');
    return passed == total;
  }

  /// 运行仅性能测试套件
  static Future<bool> runPerformanceTests() async {
    _clearOutput();
    _log('⚡ RNNoise FFI性能测试开始\n');
    
    final tests = [
      ('库加载检查', () => testLibraryLoading()),
      ('状态初始化', () => testStateInitialization()),
      ('FFI性能压测', () => testFFIPerformanceStress()),
      ('内存压力测试', () => testMemoryStress()),
      ('并发调用测试', () async => await testConcurrentCalls()),
      ('状态清理', () => testStateCleanup()),
    ];
    
    int passed = 0;
    int total = tests.length;
    
    for (final test in tests) {
      try {
        dynamic result = test.$2();
        if (result is Future<bool>) {
          result = await result;
        }
        
        if (result == true) {
          _log('✅ ${test.$1} - 通过');
          passed++;
        } else {
          _log('❌ ${test.$1} - 失败');
        }
      } catch (e) {
        _log('❌ ${test.$1} - 异常: $e');
      }
      _log('');
    }
    
    _log('🏁 性能测试完成: $passed/$total 通过');
    return passed == total;
  }
}

// 数学函数
double sin(double x) => x - (x * x * x) / 6 + (x * x * x * x * x) / 120; 