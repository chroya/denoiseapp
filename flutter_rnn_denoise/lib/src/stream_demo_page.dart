import 'package:flutter/material.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_rnn_denoise/src/audio_manager.dart';

/// 使用重构后AudioManager的演示页面
class StreamDemoPage extends StatefulWidget {
  const StreamDemoPage({Key? key}) : super(key: key);

  @override
  State<StreamDemoPage> createState() => _StreamDemoPageState();
}

class _StreamDemoPageState extends State<StreamDemoPage> {
  final AudioManager _audioManager = AudioManager();
  String _statusMessage = '请初始化';
  String? _selectedFileName;

  @override
  void initState() {
    super.initState();
    _setupCallbacks();
    _initializeAudioManager();
  }
  
  @override
  void dispose() {
    _audioManager.dispose();
    super.dispose();
  }
  
  void _setupCallbacks() {
    _audioManager.onStateChanged = () {
      if (mounted) setState(() {});
    };
    _audioManager.onStatusChanged = (status) {
      if (mounted) setState(() => _statusMessage = status);
    };
    _audioManager.onError = (error) {
      if (mounted) {
        setState(() => _statusMessage = '错误: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('错误: $error'), backgroundColor: Colors.red),
        );
      }
    };
  }

  Future<void> _initializeAudioManager() async {
    try {
      await _audioManager.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      _audioManager.onError?.call(e.toString());
    }
  }
  
  Future<void> _selectAndProcessAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        await _audioManager.selectFile(filePath);
        if(mounted) setState(() {
          _selectedFileName = _audioManager.selectedFileName;
        });
      }
    } catch (e) {
      _audioManager.onError?.call('选择文件失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('实时音频降噪'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildStatusCard(),
            const SizedBox(height: 20),
            _buildFileProcessingCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('状态面板', style: Theme.of(context).textTheme.headlineSmall),
            const Divider(),
            ListTile(
              leading: Icon(
                _audioManager.isInitialized ? Icons.check_circle : Icons.hourglass_empty,
                color: _audioManager.isInitialized ? Colors.green : Colors.grey,
              ),
              title: Text(_audioManager.isInitialized ? '已初始化' : '未初始化'),
            ),
            ListTile(
              leading: Icon(
                _audioManager.isRecording ? Icons.mic : Icons.mic_none,
                color: _audioManager.isRecording ? Colors.red : Colors.grey,
              ),
              title: Text(_audioManager.isRecording ? '正在录音...' : '录音已停止'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('当前状态'),
              subtitle: Text(_statusMessage),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileProcessingCard() {
    final bool canPlay = _audioManager.isInitialized && _selectedFileName != null;
    final bool isPlaying = _audioManager.playbackState == PlaybackState.playing;
    final bool isPaused = _audioManager.playbackState == PlaybackState.paused;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件处理', style: Theme.of(context).textTheme.headlineSmall),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.audiotrack),
              title: Text(_selectedFileName ?? '未选择文件'),
              subtitle: const Text('当前选中的音频文件'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _selectAndProcessAudioFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择音频文件'),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text('开启降噪'),
              value: _audioManager.isDenoisingEnabled,
              onChanged: (bool value) {
                _audioManager.setDenoise(value);
              },
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                  iconSize: 48.0,
                  color: canPlay ? Theme.of(context).primaryColor : Colors.grey,
                  onPressed: canPlay ? _audioManager.toggleFilePlayback : null,
                ),
                IconButton(
                  icon: const Icon(Icons.stop_circle_outlined),
                  iconSize: 48.0,
                  color: (isPlaying || isPaused) ? Theme.of(context).primaryColor : Colors.grey,
                  onPressed: (isPlaying || isPaused) ? _audioManager.stop : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}