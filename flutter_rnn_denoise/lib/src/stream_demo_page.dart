import 'package:flutter/material.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'audio_manager_stream.dart';
import 'audio_stream_processor.dart';
import 'rnnoise_test.dart';

/// 流式音频处理演示页面
class StreamDemoPage extends StatefulWidget {
  const StreamDemoPage({Key? key}) : super(key: key);

  @override
  State<StreamDemoPage> createState() => _StreamDemoPageState();
}

class _StreamDemoPageState extends State<StreamDemoPage> {
  final AudioManagerStream _audioManager = AudioManagerStream();
  
  // 状态变量
  bool _isInitialized = false;
  String _statusMessage = '未初始化';
  AudioProcessorStats? _stats;
  
  // 实时数据
  double _currentVadProbability = 0.0;
  int _totalFramesProcessed = 0;
  double _averageVadProbability = 0.0;
  
  // 音频文件可用性状态
  bool _hasRealtimeAudioFiles = false;
  
  // 文件选择处理相关状态
  bool _hasSelectedAudioFiles = false;
  String? _selectedFileName;
  
  // 定时器
  Timer? _statsTimer;
  
  // 测试相关状态
  bool _isTestRunning = false;
  String _testResults = '点击运行测试以检查FFI调用状态';
  
  @override
  void initState() {
    super.initState();
    _initializeAudioManager();
    _setupCallbacks();
    _startStatsTimer();
  }
  
  @override
  void dispose() {
    _statsTimer?.cancel();
    _audioManager.dispose();
    super.dispose();
  }
  
  /// 初始化音频管理器
  Future<void> _initializeAudioManager() async {
    try {
      await _audioManager.initialize();
      if (mounted) setState(() {
        _isInitialized = true;
        _statusMessage = '初始化完成';
      });
    } catch (e) {
      if (mounted) setState(() {
        _statusMessage = '初始化失败: $e';
      });
    }
  }
  
  /// 设置回调函数
  void _setupCallbacks() {
    _audioManager.onAudioProcessed = (result) {
      if (mounted) setState(() {
        _currentVadProbability = result.vadProbability;
        _totalFramesProcessed = result.framesProcessed;
      });
    };
    
    _audioManager.onStatusChanged = (status) {
      if (mounted) setState(() {
        _statusMessage = status;
      });
    };
    
    _audioManager.onError = (error) {
      if (mounted) setState(() {
        _statusMessage = '错误: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    };
    
    // 监听状态变更，确保UI及时更新
    _audioManager.onStateChanged = () {
      if (mounted) setState(() {
        // 强制更新UI状态
      });
    };
  }
  
  /// 启动统计信息定时器
  void _startStatsTimer() {
    _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (mounted) {
        // 检查音频文件可用性
        final hasFiles = await _audioManager.hasRealtimeAudioFiles;
        final hasSelectedFiles = await _audioManager.hasSelectedAudioFiles;
        
        setState(() {
          _hasRealtimeAudioFiles = hasFiles;
          _hasSelectedAudioFiles = hasSelectedFiles;
          
          if (_audioManager.isStreamProcessing) {
            _stats = _audioManager.streamStats;
            _averageVadProbability = _stats?.averageVadProbability ?? 0.0;
          }
          // 确保录音和处理状态也能及时更新
        });
      }
    });
  }
  
  /// 开始/停止实时处理
  Future<void> _toggleStreamProcessing() async {
    try {
      if (_audioManager.isStreamProcessing) {
        await _audioManager.stopStreamProcessing();
      } else {
        await _audioManager.startStreamProcessing();
      }
      // 强制更新UI状态
      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('实时处理操作失败: $e')),
      );
    }
  }
  
  /// 开始/停止录音
  Future<void> _toggleRecording() async {
    try {
      if (_audioManager.isRecording) {
        await _audioManager.stopRecording();
      } else {
        await _audioManager.startRecording();
      }
      // 强制更新UI状态
      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('录音操作失败: $e')),
      );
    }
  }
  
  /// 开始/停止实时录音
  Future<void> _toggleRealtimeRecording() async {
    try {
      if (_audioManager.isStreamProcessing) {
        await _audioManager.stopStreamProcessing();
      } else {
        await _audioManager.startStreamProcessing();
      }
      // 强制更新UI状态
      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('实时录音操作失败: $e')),
      );
    }
  }
  
  /// 运行FFI功能测试
  Future<void> _runFFITest() async {
    if (mounted) setState(() {
      _statusMessage = '正在运行FFI功能测试...';
    });
    
    try {
      await _audioManager.testRNNoiseFFI();
      
      if (mounted) setState(() {
        _statusMessage = 'FFI功能测试完成，请查看控制台输出';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('FFI功能测试完成！请查看控制台输出结果'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (mounted) setState(() {
        _statusMessage = 'FFI功能测试失败: $e';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('FFI功能测试失败: $e')),
      );
    }
  }
  
  /// 生成带噪声测试音频
  Future<void> _generateNoisyTestAudio() async {
    if (mounted) setState(() {
      _statusMessage = '正在生成带噪声测试音频...';
    });
    
    try {
      await _audioManager.generateNoisyTestAudio();
      
      if (mounted) setState(() {
        _statusMessage = '带噪声测试音频生成完成，可以播放对比';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('测试音频生成完成！可以播放原始音频和降噪音频进行对比'),
          backgroundColor: Colors.purple,
        ),
      );
    } catch (e) {
      if (mounted) setState(() {
        _statusMessage = '生成测试音频失败: $e';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成测试音频失败: $e')),
      );
    }
  }
  
  /// 选择音频文件进行降噪处理
  Future<void> _selectAndProcessAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'm4a', 'aac'],
      );
      
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;
        
        final file = File(filePath);
        if (!await file.exists()) {
          throw Exception('选择的文件不存在');
        }
        
        if (mounted) setState(() {
          _selectedFileName = fileName;
          _statusMessage = '已选择文件: $fileName';
        });
        
        await _audioManager.selectAudioFileAndPreparePaths(filePath);
      }
    } catch (e) {
      if (mounted) setState(() {
        _statusMessage = '选择或准备音频文件失败: $e';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择或准备音频文件失败: $e')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RNN降噪 - 流式处理'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 状态卡片
              _buildStatusCard(),
              const SizedBox(height: 16),
              
              // 实时处理控制
              _buildStreamControlCard(),
              const SizedBox(height: 16),
              
              // 文件选择处理卡片
              _buildFileProcessingCard(),
              const SizedBox(height: 16),
              
              // 统计信息
              _buildStatsCard(),
              const SizedBox(height: 16),
              
              // FFI测试卡片
              _buildFFITestCard(),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 构建状态卡片
  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '系统状态',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _isInitialized ? Icons.check_circle : Icons.error,
                  color: _isInitialized ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _audioManager.isStreamProcessing ? Icons.stream : Icons.stop,
                  color: _audioManager.isStreamProcessing ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  '实时处理: ${_audioManager.isStreamProcessing ? "运行中" : "已停止"}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  _audioManager.isRecording ? Icons.fiber_manual_record : Icons.stop,
                  color: _audioManager.isRecording ? Colors.red : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  '录音状态: ${_audioManager.isRecording ? "录音中" : "已停止"}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  _audioManager.isFileProcessing ? Icons.hourglass_bottom : Icons.done,
                  color: _audioManager.isFileProcessing ? Colors.orange : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  '文件处理: ${_audioManager.isFileProcessing ? "处理中" : "空闲"}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建流处理控制卡片
  Widget _buildStreamControlCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '实时降噪录音',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '点击按钮开始录音并实时降噪处理',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            
            // 主要控制按钮
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isInitialized ? _toggleRealtimeRecording : null,
                    icon: Icon(_audioManager.isStreamProcessing 
                        ? Icons.stop : Icons.mic),
                    label: Text(_audioManager.isStreamProcessing 
                        ? '停止实时降噪' : '开始实时降噪录音'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _audioManager.isStreamProcessing 
                          ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                // const SizedBox(width: 8),
                // Expanded(
                //   child: ElevatedButton.icon(
                //     onPressed: (_isInitialized && !_audioManager.isStreamProcessing) 
                //         ? _toggleRecording : null,
                //     icon: Icon(_audioManager.isRecording 
                //         ? Icons.stop : Icons.fiber_manual_record),
                //     label: Text(_audioManager.isRecording 
                //         ? '停止' : '仅录音'),
                //     style: ElevatedButton.styleFrom(
                //       backgroundColor: _audioManager.isRecording 
                //           ? Colors.orange : Colors.blue,
                //       foregroundColor: Colors.white,
                //       padding: const EdgeInsets.symmetric(vertical: 12),
                //     ),
                //   ),
                // ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 说明文字
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '使用说明：',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• 绿色按钮：开始录音并同时进行实时降噪\n'
                    '• 蓝色按钮：只录音不处理（用于对比）\n'
                    '• 录音完成后可播放原始音频和降噪音频进行对比',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
            ),
            
            // 测试功能区域
            const SizedBox(height: 16),
            Text(
              '调试工具',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            // const SizedBox(height: 8),
            // ElevatedButton.icon(
            //   onPressed: _isInitialized ? _runFFITest : null,
            //   icon: const Icon(Icons.bug_report),
            //   label: const Text('运行FFI功能测试'),
            //   style: ElevatedButton.styleFrom(
            //     backgroundColor: Colors.orange,
            //     foregroundColor: Colors.white,
            //     padding: const EdgeInsets.symmetric(vertical: 8),
            //   ),
            // ),
            // const SizedBox(height: 4),
            // Text(
            //   '验证RNNoise FFI调用是否正常工作',
            //   style: Theme.of(context).textTheme.bodySmall?.copyWith(
            //     color: Colors.grey[600],
            //   ),
            // ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _generateNoisyTestAudio : null,
              icon: const Icon(Icons.science),
              label: const Text('生成带噪声测试音频'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '生成包含语音信号和噪声的测试音频，验证FFI降噪效果',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            
            if (_audioManager.isStreamProcessing || _hasRealtimeAudioFiles) ...[
              const SizedBox(height: 12),
              // 音频播放控制区域
              Text(
                '实时音频播放对比',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('开启降噪 (实时流)'),
                value: _audioManager.isDenoisingEnabledForStream,
                onChanged: (bool value) {
                  _audioManager.setDenoiseEnabledForStream(value);
                  if (mounted) setState(() {});
                },
                activeColor: Colors.teal,
              ),
              ElevatedButton.icon(
                onPressed: _hasRealtimeAudioFiles ? _audioManager.toggleStreamPlayback : null,
                icon: Icon(_audioManager.isPlayingStream ? Icons.pause : Icons.play_arrow),
                label: Text(_audioManager.isPlayingStream ? '暂停播放' : '播放实时音频'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _audioManager.isPlayingStream ? Colors.orange : Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '实时VAD检测',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: _currentVadProbability,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _currentVadProbability > 0.5 ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'VAD概率: ${(_currentVadProbability * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// 构建文件处理卡片
  Widget _buildFileProcessingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '音频文件降噪处理',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '选择本地WAV文件进行处理和播放',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            
            // 文件选择按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isInitialized && !_audioManager.isFileProcessing) 
                        ? _selectAndProcessAudioFile : null,
                    icon: _audioManager.isFileProcessing 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.folder_open),
                    label: Text(_audioManager.isFileProcessing 
                        ? '降噪处理中...' : '选择音频文件 (WAV)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            
            if (_selectedFileName != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.audio_file, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '已选择: $_selectedFileName',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.teal[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            if (_hasSelectedAudioFiles) ...[
              const SizedBox(height: 12),
              Text(
                '文件播放控制',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('播放时开启降噪'),
                value: _audioManager.isDenoisingEnabledForFile,
                onChanged: (bool value) {
                  _audioManager.setDenoiseEnabledForFile(value);
                  if (mounted) setState(() {});
                },
                activeColor: Colors.teal,
              ),
              ElevatedButton.icon(
                onPressed: _hasSelectedAudioFiles 
                    ? _audioManager.toggleFilePlayback 
                    : null,
                icon: Icon(_audioManager.isPlayingFile ? Icons.pause : Icons.play_arrow),
                label: Text(_audioManager.isPlayingFile ? '暂停播放' : '播放选择文件'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _audioManager.isPlayingFile 
                      ? Colors.orange 
                      : Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            
            // 说明文字
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '支持格式：',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• WAV（当前唯一支持的格式）\n'
                    '• MP3、M4A、AAC（暂不支持，请转换为WAV）\n'
                    '• 推荐：16位PCM，48kHz采样率\n'
                    '• 处理完成后可对比播放原始文件和降噪结果',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.teal[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建统计信息卡片
  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '处理统计',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_stats != null) ...[
              _buildStatRow('总处理帧数', '${_stats!.totalFramesProcessed}'),
              _buildStatRow('平均VAD概率', '${(_stats!.averageVadProbability * 100).toStringAsFixed(1)}%'),
              _buildStatRow('处理时长', '${_stats!.totalProcessedDurationMs.toStringAsFixed(1)}ms'),
              _buildStatRow('缓冲区大小', '${_stats!.bufferSize}'),
              _buildStatRow('对象池大小', '${_stats!.poolSize}'),
            ] else ...[
              const Text('暂无统计数据'),
            ],
          ],
        ),
      ),
    );
  }
  
  /// 构建FFI测试卡片
  Widget _buildFFITestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FFI调用测试',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '检查Flutter与C层RNNoise库的FFI调用是否正常',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            
            // 测试按钮
            ElevatedButton.icon(
              onPressed: _isTestRunning ? null : _runFFITest,
              icon: _isTestRunning 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isTestRunning ? '测试中...' : '运行FFI测试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 测试结果显示区域
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '测试结果:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Text(
                        _testResults,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建统计行
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}