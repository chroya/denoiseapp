import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:file_picker/file_picker.dart';
import './audio_processor.dart';

class DenoisePage extends StatefulWidget {
  const DenoisePage({Key? key}) : super(key: key);

  @override
  State<DenoisePage> createState() => _DenoisePageState();
}

class _DenoisePageState extends State<DenoisePage> {
  final _audioProcessor = AudioProcessor();
  bool _isProcessing = false;
  bool _isPlaying = false;
  Duration? _duration;
  Duration _position = Duration.zero;
  String? _currentFile;
  String? _processedFile;

  @override
  void initState() {
    super.initState();
    _setupAudioProcessor();
  }

  void _setupAudioProcessor() {
    _audioProcessor.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });

    _audioProcessor.positionStream.listen((position) {
      setState(() {
        _position = position;
      });
    });
  }

  Future<void> _pickAudioFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowedExtensions: ['wav', 'mp3', 'm4a', 'aac'],
      );

      if (result != null && result.files.single.path != null) {
        await _loadAudioFile(result.files.single.path!);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '选择文件失败: $e');
    }
  }

  Future<void> _loadAudioFile(String filePath) async {
    try {
      await _audioProcessor.loadAudio(filePath);
      setState(() {
        _currentFile = filePath;
        _processedFile = null; // 重置处理后的文件
        _duration = _audioProcessor.duration;
      });
      Fluttertoast.showToast(msg: '文件加载成功');
    } catch (e) {
      Fluttertoast.showToast(msg: '加载音频文件失败: $e');
    }
  }

  Future<void> _processAudio() async {
    if (_currentFile == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final processedPath = await _audioProcessor.processAudio();
      if (processedPath != null) {
        setState(() {
          _processedFile = processedPath;
          _duration = _audioProcessor.duration;
        });
        Fluttertoast.showToast(msg: '处理完成！音频已降噪');
      } else {
        Fluttertoast.showToast(msg: '处理失败');
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '处理失败: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioProcessor.pause();
    } else {
      await _audioProcessor.play();
    }
  }

  Future<void> _seekToPosition(double value) async {
    final duration = _duration;
    if (duration != null) {
      final position = Duration(seconds: value.toInt());
      await _audioProcessor.player.seek(position);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _audioProcessor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音频降噪'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '原始文件: ${_currentFile?.split('/').last ?? '未选择文件'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_processedFile != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '处理后文件: ${_processedFile?.split('/').last}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_duration != null) ...[
              Slider(
                value: _position.inSeconds.toDouble(),
                max: _duration?.inSeconds.toDouble() ?? 0,
                onChanged: _seekToPosition,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(_position)),
                    Text(_formatDuration(_duration ?? Duration.zero)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickAudioFile,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('选择文件'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _currentFile == null || _isProcessing ? null : _processAudio,
                  icon: _isProcessing 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cleaning_services),
                  label: Text(_isProcessing ? '处理中...' : '降噪处理'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _currentFile == null ? null : _togglePlayback,
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(_isPlaying ? '暂停' : '播放'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            if (_processedFile != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                '降噪完成！',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '当前播放的是降噪后的音频',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
