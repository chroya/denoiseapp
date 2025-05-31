import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import './rnnoise_processor.dart';

class AudioProcessor {
  final AudioPlayer _player = AudioPlayer();
  final _rnnoise = RNNoiseProcessor();
  String? _currentAudioPath;
  bool _isProcessing = false;

  Future<void> loadAudio(String audioPath) async {
    _currentAudioPath = audioPath;
    await _player.setFilePath(audioPath);
  }

  Future<void> play() async {
    if (_currentAudioPath == null) return;
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
    _rnnoise.dispose();
  }

  Future<String?> processAudio() async {
    if (_currentAudioPath == null || _isProcessing) return null;
    _isProcessing = true;

    try {
      final inputFile = File(_currentAudioPath!);
      if (!await inputFile.exists()) {
        throw Exception('输入文件不存在');
      }

      // 获取临时目录用于存储处理后的文件
      final tempDir = await getTemporaryDirectory();
      final outputPath = path.join(
        tempDir.path,
        'denoised_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      // 处理音频文件
      await _rnnoise.processFile(_currentAudioPath!, outputPath);

      // 更新当前音频路径并加载新文件
      _currentAudioPath = outputPath;
      await _player.setFilePath(outputPath);

      return outputPath;
    } catch (e) {
      print('音频处理错误: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  bool get isPlaying => _player.playing;
  Duration? get duration => _player.duration;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  
  // 提供对播放器的访问以便进行 seek 操作
  AudioPlayer get player => _player;
} 