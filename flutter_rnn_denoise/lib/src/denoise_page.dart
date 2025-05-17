import 'package:flutter/material.dart';
import 'audio_manager.dart';

class DenoisePage extends StatefulWidget {
  const DenoisePage({Key? key}) : super(key: key);

  @override
  _DenoisePageState createState() => _DenoisePageState();
}

class _DenoisePageState extends State<DenoisePage> {
  final AudioManager _audioManager = AudioManager();
  bool _isInitialized = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeAudioManager();
  }

  Future<void> _initializeAudioManager() async {
    try {
      await _audioManager.initialize();
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      _showErrorDialog('初始化失败', e.toString());
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRecordButton() async {
    if (_audioManager.isRecording) {
      try {
        await _audioManager.stopRecording();
      } catch (e) {
        _showErrorDialog('停止录音失败', e.toString());
        // 即使出现异常，也要强制更新状态，避免UI卡在录音状态
        setState(() {
          // 强制刷新UI
        });
      }
    } else {
      try {
        await _audioManager.startRecording();
      } catch (e) {
        _showErrorDialog('录音失败', e.toString());
      }
    }
    setState(() {});
  }

  Future<void> _handlePlayOriginalButton() async {
    if (_audioManager.isPlaying) {
      await _audioManager.stopPlayingOriginal();
    } else {
      try {
        await _audioManager.playOriginal();
      } catch (e) {
        _showErrorDialog('播放失败', e.toString());
      }
    }
    setState(() {});
  }

  Future<void> _handleProcessButton() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final success = await _audioManager.processAudio();
      if (!success) {
        _showErrorDialog('处理失败', '音频处理返回错误');
      }
    } catch (e) {
      _showErrorDialog('处理失败', e.toString());
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _handlePlayProcessedButton() async {
    if (_audioManager.isPlayingProcessed) {
      await _audioManager.stopPlayingProcessed();
    } else {
      try {
        await _audioManager.playProcessed();
      } catch (e) {
        _showErrorDialog('播放失败', e.toString());
      }
    }
    setState(() {});
  }

  void _handleRealTimeModeToggle() {
    _audioManager.toggleRealTimeMode();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('RNN语音降噪'),
        backgroundColor: Colors.blue,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue, Colors.indigo],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            _buildRecordButton(),
            const SizedBox(height: 20),
            _buildButtonRow(),
            const SizedBox(height: 20),
            _buildProcessButton(),
            const SizedBox(height: 20),
            _buildRealTimeModeToggle(),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordButton() {
    return GestureDetector(
      onTap: _handleRecordButton,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _audioManager.isRecording ? Colors.red : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Icon(
          _audioManager.isRecording ? Icons.stop : Icons.mic,
          size: 50,
          color: _audioManager.isRecording ? Colors.white : Colors.red,
        ),
      ),
    );
  }

  Widget _buildButtonRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildActionButton(
          icon: _audioManager.isPlaying ? Icons.stop : Icons.play_arrow,
          label: '原始音频',
          onPressed: _handlePlayOriginalButton,
          isEnabled: !_audioManager.isRecording,
        ),
        const SizedBox(width: 40),
        _buildActionButton(
          icon: _audioManager.isPlayingProcessed ? Icons.stop : Icons.play_arrow,
          label: '降噪音频',
          onPressed: _handlePlayProcessedButton,
          isEnabled: !_audioManager.isRecording,
        ),
      ],
    );
  }

  Widget _buildProcessButton() {
    return _buildActionButton(
      icon: Icons.auto_fix_high,
      label: '降噪处理',
      onPressed: _isProcessing ? null : _handleProcessButton,
      isEnabled: !_audioManager.isRecording && !_isProcessing,
      isLoading: _isProcessing,
    );
  }

  Widget _buildRealTimeModeToggle() {
    return SwitchListTile(
      title: const Text(
        '实时降噪模式',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      value: _audioManager.isRealTimeEnabled,
      onChanged: (value) => _handleRealTimeModeToggle(),
      activeColor: Colors.green,
      inactiveTrackColor: Colors.grey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 40),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool isEnabled,
    bool isLoading = false,
  }) {
    return ElevatedButton(
      onPressed: isEnabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Icon(icon),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioManager.dispose();
    super.dispose();
  }
}
