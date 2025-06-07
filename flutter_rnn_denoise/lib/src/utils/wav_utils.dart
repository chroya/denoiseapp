import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

class WavUtils {
  /// 从PCM数据创建WAV格式的字节数据（内存中）
  static Uint8List createWavFromPCM(Uint8List pcmData, int sampleRate, int channels, int bitsPerSample) {
    final dataSize = pcmData.length;
    final totalSize = 44 + dataSize;
    
    final wavData = Uint8List(totalSize);
    final wavView = ByteData.view(wavData.buffer);
    
    // RIFF chunk
    wavData.setRange(0, 4, 'RIFF'.codeUnits);
    wavView.setUint32(4, totalSize - 8, Endian.little);
    wavData.setRange(8, 12, 'WAVE'.codeUnits);
    
    // fmt chunk
    wavData.setRange(12, 16, 'fmt '.codeUnits);
    wavView.setUint32(16, 16, Endian.little); // chunk size
    wavView.setUint16(20, 1, Endian.little); // PCM format
    wavView.setUint16(22, channels, Endian.little);
    wavView.setUint32(24, sampleRate, Endian.little);
    wavView.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little); // byte rate
    wavView.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little); // block align
    wavView.setUint16(34, bitsPerSample, Endian.little);
    
    // data chunk
    wavData.setRange(36, 40, 'data'.codeUnits);
    wavView.setUint32(40, dataSize, Endian.little);
    wavData.setRange(44, 44 + dataSize, pcmData);
    
    return wavData;
  }

  /// 将多声道PCM数据混音为单声道
  static Uint8List downmixToMono(Uint8List multiChannelPcm, int bitsPerSample, int numChannels) {
      if (numChannels <= 1) return multiChannelPcm;
      if (bitsPerSample != 16) {
          print("Warning: Only 16-bit audio is supported for downmixing. Skipping.");
          return multiChannelPcm;
      }

      int bytesPerSample = bitsPerSample ~/ 8;
      int frameSize = bytesPerSample * numChannels;
      int frameCount = multiChannelPcm.lengthInBytes ~/ frameSize;
      
      final monoPcm = Uint8List(frameCount * bytesPerSample);
      final multiChannelView = ByteData.view(multiChannelPcm.buffer, multiChannelPcm.offsetInBytes, multiChannelPcm.lengthInBytes);
      final monoView = ByteData.view(monoPcm.buffer);

      for (int i = 0; i < frameCount; i++) {
          int frameOffset = i * frameSize;
          int sum = 0;
          for (int c = 0; c < numChannels; c++) {
              sum += multiChannelView.getInt16(frameOffset + c * bytesPerSample, Endian.little);
          }
          int avgSample = (sum / numChannels).round();
          monoView.setInt16(i * bytesPerSample, avgSample, Endian.little);
      }
      
      return monoPcm;
  }

  /// 解析WAV文件头以获取音频信息
  static Future<WavHeaderInfo> parseWavHeader(RandomAccessFile raf) async {
    if (await raf.length() < 44) {
      throw Exception("File too short to be a valid WAV.");
    }
    
    final headerCheckBytes = await raf.read(math.min(200, await raf.length())); 
    await raf.setPosition(0); 

    if (String.fromCharCodes(headerCheckBytes.sublist(0,4)) != "RIFF" || 
        String.fromCharCodes(headerCheckBytes.sublist(8,12)) != "WAVE") {
        throw Exception("Selected file is not a valid WAV file.");
    }

    final headerBytes = ByteData.view(headerCheckBytes.buffer, headerCheckBytes.offsetInBytes, headerCheckBytes.length);
    
    int numChannels = headerBytes.getUint16(22, Endian.little);
    int originalSampleRate = headerBytes.getUint32(24, Endian.little);
    int bitsPerSample = headerBytes.getUint16(34, Endian.little);
    
    int dataStartPosition = 44;
    int searchPos = 12;
    bool foundData = false;
    while(searchPos < headerCheckBytes.length - 8) {
        String chunkId = String.fromCharCodes(headerCheckBytes.sublist(searchPos, searchPos + 4));
        if (searchPos + 8 > headerCheckBytes.length) break; 
        int chunkSize = ByteData.view(headerCheckBytes.buffer, headerCheckBytes.offsetInBytes + searchPos + 4, 4).getUint32(0, Endian.little);
        
        if (chunkId == 'data') {
            dataStartPosition = searchPos + 8;
            foundData = true;
            break;
        }
        searchPos += (8 + chunkSize);
        if (chunkSize % 2 != 0 && searchPos < headerCheckBytes.length) searchPos++; 
    }
    if (!foundData) {
       throw Exception("Could not find 'data' chunk in WAV.");
    }

    return WavHeaderInfo(
      numChannels: numChannels,
      sampleRate: originalSampleRate,
      bitsPerSample: bitsPerSample,
      dataStartPosition: dataStartPosition,
    );
  }

   /// 附加WAV块
  static Uint8List appendWavChunks(Uint8List baseWav, Uint8List newWav, int sampleRate) {
    final basePcm = baseWav.sublist(44);
    final newPcm = newWav.sublist(44);

    final combinedPcm = Uint8List(basePcm.length + newPcm.length);
    combinedPcm.setRange(0, basePcm.length, basePcm);
    combinedPcm.setRange(basePcm.length, combinedPcm.length, newPcm);

    return createWavFromPCM(combinedPcm, sampleRate, 1, 16);
  }
}

class WavHeaderInfo {
  final int numChannels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataStartPosition;

  WavHeaderInfo({
    required this.numChannels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataStartPosition,
  });
} 