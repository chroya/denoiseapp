import 'package:flutter/material.dart';
import 'rnnoise_test.dart';

class PerformanceTestPage extends StatefulWidget {
  const PerformanceTestPage({Key? key}) : super(key: key);

  @override
  State<PerformanceTestPage> createState() => _PerformanceTestPageState();
}

class _PerformanceTestPageState extends State<PerformanceTestPage> {
  bool _isRunning = false;
  String _testOutput = '';
  ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _runAllTests() async {
    if (_isRunning) return;
    
    setState(() {
      _isRunning = true;
      _testOutput = '';
    });

    try {
      await RNNoiseTest.runAllTests();
      final output = RNNoiseTest.getOutput();
      setState(() {
        _testOutput = output;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _testOutput = '测试运行失败: $e';
      });
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<void> _runPerformanceTests() async {
    if (_isRunning) return;
    
    setState(() {
      _isRunning = true;
      _testOutput = '';
    });

    try {
      await RNNoiseTest.runPerformanceTests();
      final output = RNNoiseTest.getOutput();
      setState(() {
        _testOutput = output;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _testOutput = '性能测试运行失败: $e';
      });
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  void _clearOutput() {
    setState(() {
      _testOutput = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FFI性能测试'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            onPressed: _isRunning ? null : _clearOutput,
            icon: const Icon(Icons.clear),
            tooltip: '清空输出',
          ),
        ],
      ),
      body: Column(
        children: [
          // 控制按钮区域
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isRunning ? null : _runPerformanceTests,
                        icon: _isRunning 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.speed),
                        label: Text(_isRunning ? '测试中...' : '运行性能测试'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(12),
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isRunning ? null : _runAllTests,
                        icon: _isRunning 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.playlist_play),
                        label: Text(_isRunning ? '测试中...' : '完整测试套件'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(12),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 测试说明
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[600], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '性能测试说明',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• 高频单帧调用: 1000次快速FFI调用测试\n'
                        '• 多帧批处理: 测试批量数据处理性能\n'
                        '• 内存压力测试: 大数据量处理测试\n'
                        '• 并发调用测试: 多线程安全性测试',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 输出显示区域
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16.0),
              child: _testOutput.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '选择上方按钮开始测试',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '性能测试将显示FFI调用的延迟、吞吐量和并发性能',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      controller: _scrollController,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          _testOutput,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.green,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
} 