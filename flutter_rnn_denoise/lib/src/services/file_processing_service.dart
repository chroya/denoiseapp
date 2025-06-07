import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path_helper;
import '../utils/wav_utils.dart';
import 'denoise_service.dart';

const int _SAMPLE_RATE = 48000;
const int _CHUNK_DURATION_SECONDS = 1;

class FileProcessingService {
  final DenoiseService _denoiseService;
  final String _appDir;

  bool _isProcessing = false;
  bool _stopProcessingFlag = false;
  StreamController<Uint8List>? _processedStreamController;

  FileProcessingService(this._denoiseService, this._appDir);

  bool get isProcessing => _isProcessing;

  /// Processes the selected audio file and returns a stream of denoised WAV chunks.
  Stream<Uint8List> processFile(String filePath) {
    if (_isProcessing) {
      throw Exception("Another file is already being processed.");
    }
    _isProcessing = true;
    _stopProcessingFlag = false;
    _processedStreamController = StreamController<Uint8List>();

    _startProcessing(filePath);

    return _processedStreamController!.stream;
  }

  Future<void> _startProcessing(String filePath) async {
    RandomAccessFile? raf;
    try {
      raf = await File(filePath).open(mode: FileMode.read);
      final headerInfo = await WavUtils.parseWavHeader(raf);

      print('--- WAV Header Info (File Processing) ---');
      print('Sample Rate: ${headerInfo.sampleRate}Hz, Channels: ${headerInfo.numChannels}, BitsPerSample: ${headerInfo.bitsPerSample}bit');
      if (headerInfo.sampleRate != _SAMPLE_RATE) {
        print('⚠️ Sample rate mismatch: File is ${headerInfo.sampleRate}Hz, RNNoise requires ${_SAMPLE_RATE}Hz. This may affect pitch.');
      }
      
      await raf.setPosition(headerInfo.dataStartPosition);
      int totalAudioBytes = await raf.length() - headerInfo.dataStartPosition;
      
      int samplesPerChunk = _SAMPLE_RATE * _CHUNK_DURATION_SECONDS;
      int bytesPerChunkTarget = samplesPerChunk * (headerInfo.bitsPerSample ~/ 8) * headerInfo.numChannels;

      while (totalAudioBytes > 0 && !_stopProcessingFlag) {
        int bytesToRead = bytesPerChunkTarget < totalAudioBytes ? bytesPerChunkTarget : totalAudioBytes;
        if (bytesToRead <= 0) break;
        
        Uint8List pcmChunkBytes = await raf.read(bytesToRead);
        if (pcmChunkBytes.isEmpty) break;

        // Downmix to mono if necessary
        if (headerInfo.numChannels > 1) {
            pcmChunkBytes = WavUtils.downmixToMono(pcmChunkBytes, headerInfo.bitsPerSample, headerInfo.numChannels);
        }
        
        totalAudioBytes -= bytesToRead;

        // Denoise the chunk
        final processedChunk = await _denoiseService.processAudioChunk(pcmChunkBytes);
        
        if (processedChunk != null && !_stopProcessingFlag) {
          final wavData = WavUtils.createWavFromPCM(processedChunk, _SAMPLE_RATE, 1, 16);
          _processedStreamController?.add(wavData);
        }
        
        await Future.delayed(Duration(milliseconds: 50)); // Prevent blocking UI thread
      }
    } catch (e, s) {
      print("Error in _startProcessing: $e\nStackTrace: $s");
      _processedStreamController?.addError(e, s);
    } finally {
      await raf?.close();
      _isProcessing = false;
      await _processedStreamController?.close();
    }
  }

  /// Signals the ongoing processing loop to stop.
  void stopProcessing() {
    _stopProcessingFlag = true;
  }
} 