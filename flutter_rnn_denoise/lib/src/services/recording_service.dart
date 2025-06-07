import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:record/record.dart';
import 'package:path/path.dart' as path_helper;

const int _SAMPLE_RATE = 48000;

class RecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  final String _recordingPath;
  Timer? _audioReadTimer;
  int _audioFileReadPosition = 0;
  bool _isRecording = false;

  RecordingService(String appDir) 
      : _recordingPath = path_helper.join(appDir, 'temp_recording.wav');

  bool get isRecording => _isRecording;

  /// Starts recording and returns a stream of raw PCM audio data.
  Stream<Uint8List> startRecording() {
    if (_isRecording) {
      throw Exception("Recording is already in progress.");
    }

    final controller = StreamController<Uint8List>.broadcast();
    
    _isRecording = true;
    _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: _SAMPLE_RATE,
        numChannels: 1,
        bitRate: 16,
      ),
      path: _recordingPath,
    ).then((_) {
      _audioFileReadPosition = 44; // Skip WAV header
      _audioReadTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
        if (!_isRecording) {
          timer.cancel();
          return;
        }
        try {
          final audioChunk = await _readAudioDataFromFile();
          if (audioChunk != null && audioChunk.isNotEmpty) {
            controller.add(audioChunk);
          }
        } catch (e) {
          controller.addError(Exception("Failed to read audio data: $e"));
        }
      });
    }).catchError((e) {
      _isRecording = false;
      controller.addError(Exception("Failed to start recorder: $e"));
      controller.close();
    });

    return controller.stream;
  }

  /// Stops the recording process.
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    _audioReadTimer?.cancel();
    await _recorder.stop();
    
    // Clean up the temporary recording file
    try {
      final file = File(_recordingPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print("Error deleting temporary recording file: $e");
    }
  }

  Future<Uint8List?> _readAudioDataFromFile() async {
    final file = File(_recordingPath);
    if (!await file.exists()) {
      return null;
    }

    final fileBytes = await file.readAsBytes();
    if (fileBytes.length <= _audioFileReadPosition) {
      return null;
    }

    const samplesToRead = _SAMPLE_RATE ~/ 10; // ~100ms of audio
    const bytesToRead = samplesToRead * 2; // 16-bit PCM
    final endPos = math.min(_audioFileReadPosition + bytesToRead, fileBytes.length);

    final actualBytesToRead = ((endPos - _audioFileReadPosition) ~/ 2) * 2;
    if (actualBytesToRead <= 0) {
      return null;
    }

    final actualEndPos = _audioFileReadPosition + actualBytesToRead;
    final audioBytes = fileBytes.sublist(_audioFileReadPosition, actualEndPos);
    _audioFileReadPosition = actualEndPos;
    
    return audioBytes;
  }

  Future<void> dispose() async {
    await stopRecording();
    await _recorder.dispose();
  }
}

// A simple math.min implementation to avoid importing dart:math for just one function
int min(int a, int b) => a < b ? a : b; 