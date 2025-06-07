import 'dart:async';
import 'dart:typed_data';
import '../rnnoise_ffi.dart';

const int _FRAME_SIZE = 480;

class DenoiseService {
  final RNNoiseFFI _rnnoise;

  DenoiseService(this._rnnoise);

  /// Processes a stream of raw PCM audio data and returns a stream of denoised audio.
  ///
  /// The input stream should be 16-bit PCM mono audio at the required sample rate.
  Stream<Uint8List> processStream(Stream<Uint8List> inputStream) {
    final StreamController<Uint8List> controller = StreamController();
    final List<int> rawAudioBuffer = [];

    inputStream.listen(
      (audioData) {
        final samples = Int16List.view(audioData.buffer);
        rawAudioBuffer.addAll(samples);

        while (rawAudioBuffer.length >= _FRAME_SIZE) {
          final frameData = rawAudioBuffer.take(_FRAME_SIZE).toList();
          rawAudioBuffer.removeRange(0, _FRAME_SIZE);

          final inputFrameF32 = Float32List(_FRAME_SIZE);
          for (int i = 0; i < _FRAME_SIZE; i++) {
            inputFrameF32[i] = frameData[i] / 32768.0;
          }

          final result = _rnnoise.processFrames(inputFrameF32, 1);
          final processedChunkF32 = result.processedAudio;

          // Convert back to Int16 PCM
          final pcmData = Uint8List(processedChunkF32.length * 2);
          final pcmByteData = ByteData.view(pcmData.buffer);
          for (int i = 0; i < processedChunkF32.length; i++) {
            int sample = (processedChunkF32[i] * 32767).round().clamp(-32768, 32767);
            pcmByteData.setInt16(i * 2, sample, Endian.little);
          }
          controller.add(pcmData);
        }
      },
      onError: (error) => controller.addError(error),
      onDone: () {
        // Potentially process any remaining data in rawAudioBuffer if needed
        controller.close();
      },
    );

    return controller.stream;
  }

  /// Processes a single chunk of PCM data.
  /// This is useful for file-based processing where data arrives in large chunks.
  Future<Uint8List?> processAudioChunk(Uint8List pcmChunkBytes) async {
    try {
      List<Float32List> processedFramesInChunk = [];
      
      ByteData pcmChunkByteData = ByteData.view(pcmChunkBytes.buffer, pcmChunkBytes.offsetInBytes, pcmChunkBytes.lengthInBytes);
      int currentByteOffset = 0;

      while(currentByteOffset + (_FRAME_SIZE * 2) <= pcmChunkByteData.lengthInBytes) {
          final inputFrameInt16 = Int16List(_FRAME_SIZE);
          for(int i = 0; i < _FRAME_SIZE; i++){
              inputFrameInt16[i] = pcmChunkByteData.getInt16(currentByteOffset + i * 2, Endian.little);
          }
          currentByteOffset += _FRAME_SIZE * 2;
          
          final inputFrameF32 = Float32List(_FRAME_SIZE);
          for (int i = 0; i < _FRAME_SIZE; i++) inputFrameF32[i] = inputFrameInt16[i] / 32768.0;
          
          final result = _rnnoise.processFrames(inputFrameF32, 1);
          processedFramesInChunk.add(result.processedAudio);
      }

      if (processedFramesInChunk.isNotEmpty) {
        Float32List processedChunkF32 = _mergeAudioFrames(processedFramesInChunk);
        
        final pcmData = Uint8List(processedChunkF32.length * 2);
        final pcmByteData = ByteData.view(pcmData.buffer);
        for (int i = 0; i < processedChunkF32.length; i++) {
          int sample = (processedChunkF32[i] * 32767).round().clamp(-32768, 32767);
          pcmByteData.setInt16(i * 2, sample, Endian.little);
        }
        return pcmData;
      }
      return null;
    } catch (e) {
      print("Error processing audio chunk: $e");
      return null;
    }
  }

  Float32List _mergeAudioFrames(List<Float32List> frames) {
    if (frames.isEmpty) return Float32List(0);
    
    final totalLength = frames.fold<int>(0, (sum, frame) => sum + frame.length);
    final merged = Float32List(totalLength);
    
    int offset = 0;
    for (final frame in frames) {
      merged.setRange(offset, offset + frame.length, frame);
      offset += frame.length;
    }
    return merged;
  }
} 