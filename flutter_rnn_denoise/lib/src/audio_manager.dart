import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path/path.dart' as path_helper;
import 'package:record/record.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'rnnoise_ffi.dart';

/// 音频管理器类，负责录音和播放
class AudioManager {
  // 单例
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  // 录音器和播放器
  final _recorder = AudioRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final FlutterSoundPlayer _playerProcessed = FlutterSoundPlayer();
  
  // RNNoise接口
  final RNNoiseFFI _rnnoise = RNNoiseFFI();
  
  // 状态
  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  bool _isPlayerProcessedInitialized = false;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isPlayingProcessed = false;
  bool _isRealTimeEnabled = false;
  
  // 文件路径
  late String _appDir;
  late String _recordingPath;
  late String _processedPath;
  
  // 添加新的成员变量
  bool _hasRecordedData = false;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  
  // 获取状态
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  bool get isPlayingProcessed => _isPlayingProcessed;
  bool get isRealTimeEnabled => _isRealTimeEnabled;
  
  /// 初始化音频管理器
  Future<void> initialize() async {
    // 先请求权限
    await _requestPermissions();
    
    // 初始化路径
    await _initializePaths();
    
    // 初始化录音器和播放器
    await _initializeAudioSession();
    await _initializeRecorder();
    await _initializePlayers();
  }
  
  /// 请求所需权限
  Future<void> _requestPermissions() async {
    // 请求麦克风权限
    final micStatus = await Permission.microphone.request();
    if (micStatus != PermissionStatus.granted) {
      throw Exception('需要麦克风权限才能录音');
    }
    
    // 请求存储权限（Android需要）
    if (Platform.isAndroid) {
      // 检测Android版本
      bool isAndroid13OrHigher = false;
      bool isAndroid11OrHigher = false;
      try {
        final sdkVersion = int.parse(Platform.operatingSystemVersion.split(' ').last);
        isAndroid13OrHigher = sdkVersion >= 33;
        isAndroid11OrHigher = sdkVersion >= 30;
      } catch (e) {
        // 解析失败，假设是较低版本
        isAndroid13OrHigher = true;
        isAndroid11OrHigher = true;
      }
      
      if (isAndroid13OrHigher) {
        // Android 13及以上版本使用媒体权限
        final audioStatus = await Permission.audio.request();
        if (audioStatus != PermissionStatus.granted) {
          throw Exception('需要音频访问权限才能保存录音');
        }
      } else if (isAndroid11OrHigher) {
        // Android 11及以上版本使用MANAGE_EXTERNAL_STORAGE权限
        if (!await Permission.manageExternalStorage.isGranted) {
          final status = await Permission.manageExternalStorage.request();
          if (status != PermissionStatus.granted) {
            // 如果权限未授予，引导用户到设置页面
            if (await Permission.manageExternalStorage.isPermanentlyDenied) {
              await openAppSettings();
            }
            throw Exception('需要文件管理权限才能保存录音');
          }
        }
      } else {
        // Android 10及以下版本使用传统存储权限
        final storageStatus = await Permission.storage.request();
        if (storageStatus != PermissionStatus.granted) {
          throw Exception('需要存储权限才能保存录音');
        }
      }
    }
  }
  
  /// 初始化音频会话
  Future<void> _initializeAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.audibilityEnforced,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientExclusive,
    ));
    
    // 监听音频会话中断
    session.interruptionEventStream.listen((event) {
      print('音频会话中断: $event');
      if (event.begin) {
        // 中断开始
        if (_isRecording) {
          stopRecording().catchError((e) => print('停止录音失败: $e'));
        }
      }
    });
  }
  
  /// 初始化录音器
  Future<void> _initializeRecorder() async {
    try {
      // 检查录音器是否可用
      final isRecorderReady = await _recorder.isEncoderSupported(AudioEncoder.pcm16bits);
      
      if (!isRecorderReady) {
        throw Exception('录音器不支持PCM 16位编码');
      }
      
      _isRecorderInitialized = true;
      print('录音器初始化成功');
    } catch (e) {
      print('录音器初始化失败: $e');
      _isRecorderInitialized = false;
      throw Exception('录音器初始化失败: $e');
    }
  }
  
  /// 初始化播放器
  Future<void> _initializePlayers() async {
    await _player.openPlayer();
    _isPlayerInitialized = true;
    
    await _playerProcessed.openPlayer();
    _isPlayerProcessedInitialized = true;
  }
  
  /// 初始化文件路径
  Future<void> _initializePaths() async {
    try {
      Directory? directory;
      
      // 根据平台使用不同的目录策略
      if (Platform.isAndroid) {
        // 尝试多种可能的目录
        try {
          directory = await getExternalStorageDirectory();
        } catch (e) {
          print('无法获取外部存储目录: $e');
        }
        
        if (directory == null) {
          try {
            // 尝试获取应用专属缓存目录
            directory = await getApplicationCacheDirectory();
          } catch (e) {
            print('无法获取应用缓存目录: $e');
          }
        }
        
        if (directory == null) {
          // 如果仍然无法获取目录，则使用应用文档目录
          directory = await getApplicationDocumentsDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      _appDir = path_helper.join(directory.path, 'audio_files');
      
      // 创建音频目录
      final audioDir = Directory(_appDir);
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }
      
      _recordingPath = path_helper.join(_appDir, 'recording.pcm');
      _processedPath = path_helper.join(_appDir, 'processed.pcm');
      
      // 测试文件是否可写
      try {
        final testFile = File(path_helper.join(_appDir, 'test.txt'));
        await testFile.writeAsString('测试文件权限');
        await testFile.delete();
        print('测试文件可写: $_appDir');
      } catch (e) {
        print('文件写入测试失败: $e');
        throw Exception('目录不可写: $_appDir');
      }
    } catch (e) {
      throw Exception('无法初始化文件路径: $e');
    }
  }
  
  /// 开始录音
  Future<void> startRecording() async {
    if (!_isRecorderInitialized) {
      throw Exception('录音器未初始化');
    }
    
    if (_isRecording) {
      print('已经在录音中');
      return;
    }
    
    try {
      // 先测试各种目录的权限和可写性
      await _testDirectories();
      
      // 确保目录存在
      final directory = Directory(path_helper.dirname(_recordingPath));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // 如果文件已存在，先删除
      final targetFile = File(_recordingPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      // 重置状态
      _hasRecordedData = false;
      
      // 配置音频会话
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionMode: AVAudioSessionMode.measurement,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));

      print('开始录音到: $_recordingPath');
      
      // 开始录音，直接录制到目标文件
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          bitRate: 256000, // 16位 * 16000Hz = 256000 bits/s
          sampleRate: 16000, // 16kHz采样率
          numChannels: 1, // 单声道
        ),
        path: _recordingPath,
      );
      
      // 订阅振幅变化，用于监控录音状态
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
        final decibels = amplitude.current;
        print('录音进度：amplitude=${amplitude.current}, peak=${amplitude.max}');
        
        if (decibels > 1.0) {
          _hasRecordedData = true;
        }
      });
      
      _isRecording = true;
      print('录音开始成功');
    } catch (e, stackTrace) {
      print('录音启动失败: $e');
      print('错误堆栈: $stackTrace');
      _isRecording = false;
      throw Exception('录音启动失败: $e');
    }
  }
  
  /// 测试各种目录的权限和可写性
  Future<void> _testDirectories() async {
    print('\n开始测试各种目录的可写性');
    
    try {
      final tempDir = await getTemporaryDirectory();
      print('临时目录: ${tempDir.path}');
      final tempTestFile = File('${tempDir.path}/test_write.txt');
      await tempTestFile.writeAsString('test');
      print('临时目录可写');
      await tempTestFile.delete();
    } catch (e) {
      print('临时目录写入测试失败: $e');
    }
    
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      print('应用文档目录: ${appDocDir.path}');
      final docTestFile = File('${appDocDir.path}/test_write.txt');
      await docTestFile.writeAsString('test');
      print('应用文档目录可写');
      await docTestFile.delete();
    } catch (e) {
      print('应用文档目录写入测试失败: $e');
    }
    
    if (Platform.isAndroid) {
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          print('外部存储目录: ${externalDir.path}');
          final extTestFile = File('${externalDir.path}/test_write.txt');
          await extTestFile.writeAsString('test');
          print('外部存储目录可写');
          await extTestFile.delete();
        } else {
          print('外部存储目录不可用');
        }
      } catch (e) {
        print('外部存储目录写入测试失败: $e');
      }
      
      try {
        final cacheDir = await getApplicationCacheDirectory();
        print('缓存目录: ${cacheDir.path}');
        final cacheTestFile = File('${cacheDir.path}/test_write.txt');
        await cacheTestFile.writeAsString('test');
        print('缓存目录可写');
        await cacheTestFile.delete();
      } catch (e) {
        print('缓存目录写入测试失败: $e');
      }
    }
    
    print('目录测试完成\n');
  }
  
  /// 停止录音
  Future<void> stopRecording() async {
    if (!_isRecording) {
      print('没有正在进行的录音');
      return;
    }
    
    print('AudioManager: 停止录音开始');
    
    // 先重置状态，确保UI能正确更新
    _isRecording = false;
    
    try {
      // 取消振幅监听
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      
      // 检查是否有录音数据
      if (!_hasRecordedData) {
        print('AudioManager_WARNING: 未检测到有效的录音数据');
      }
      
      // 停止录音
      await _recorder.stop();
      print('AudioManager: 录音已停止');
      
      // 验证文件是否已保存
      final recordedFile = File(_recordingPath);
      if (!await recordedFile.exists()) {
        print('AudioManager_ERROR: 录音文件不存在: $_recordingPath');
        throw Exception('录音文件不存在');
      }
      
      final fileSize = await recordedFile.length();
      print('AudioManager_INFO: 录音文件大小: $fileSize bytes');
      
      if (fileSize <= 0) {
        print('AudioManager_ERROR: 录音文件大小为0，创建合成的静音文件');
        
        // 创建一个包含2秒16kHz、16位单声道静音的PCM文件
        // 16kHz * 2秒 * 2字节/样本 = 64000字节
        final silenceData = Uint8List(64000);
        await recordedFile.writeAsBytes(silenceData);
        print('AudioManager_WARNING: 创建了合成的静音PCM文件: $_recordingPath, 大小: ${await recordedFile.length()} bytes');
      } else {
        print('AudioManager_SUCCESS: 录音文件已保存: $_recordingPath, 大小: $fileSize bytes');
      }
    } catch (e, stackTrace) {
      print('AudioManager_ERROR: stopRecording 过程中发生错误: $e');
      print('AudioManager_ERROR: 错误堆栈: $stackTrace');
      throw Exception('停止录音失败: $e');
    } finally {
      // 确保状态被重置
      _isRecording = false;
      _hasRecordedData = false;
      print('AudioManager: stopRecording 方法执行完毕');
    }
  }
  
  /// 处理音频（降噪）
  Future<bool> processAudio() async {
    final inputFile = File(_recordingPath);
    if (!await inputFile.exists()) {
      Fluttertoast.showToast(
        msg: "录音文件不存在",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
      );
      throw Exception('录音文件不存在');
    }
    
    Fluttertoast.showToast(
      msg: "正在进行降噪处理...",
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.CENTER,
    );
    
    final result = _rnnoise.processAudioFile(_recordingPath, _processedPath);
    
    if (result == 0) {
      Fluttertoast.showToast(
        msg: "降噪处理完成",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
      );
      return true;
    } else {
      Fluttertoast.showToast(
        msg: "降噪处理失败",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
      );
      return false;
    }
  }
  
  /// 播放原始录音
  Future<void> playOriginal() async {
    if (!_isPlayerInitialized) {
      throw Exception('播放器未初始化');
    }
    
    if (_isPlaying) {
      print('已经在播放中');
      return;
    }
    
    try {
      final file = File(_recordingPath);
      if (!await file.exists()) {
        throw Exception('录音文件不存在：$_recordingPath');
      }
      
      final size = await file.length();
      if (size == 0) {
        throw Exception('录音文件大小为0，无法播放');
      }
      
      print('开始播放文件: $_recordingPath (大小: $size bytes)');
      _isPlaying = true;
      
      // 配置音频会话
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
      ));
      
      await _player.startPlayer(
        fromURI: _recordingPath,
        codec: Codec.pcm16,
        sampleRate: 16000,
        numChannels: 1,
        whenFinished: () {
          print('播放完成');
          _isPlaying = false;
        },
      );
    } catch (e, stackTrace) {
      print('播放失败: $e');
      print('错误堆栈: $stackTrace');
      _isPlaying = false;
      throw Exception('播放失败: $e');
    }
  }
  
  /// 停止播放原始录音
  Future<void> stopPlayingOriginal() async {
    if (!_isPlaying) return;
    
    await _player.stopPlayer();
    _isPlaying = false;
  }
  
  /// 播放处理后的音频
  Future<void> playProcessed() async {
    if (!_isPlayerProcessedInitialized) {
      throw Exception('播放器未初始化');
    }
    
    final processedFile = File(_processedPath);
    if (!await processedFile.exists()) {
      throw Exception('处理后的音频文件不存在');
    }
    
    _isPlayingProcessed = true;
    await _playerProcessed.startPlayer(
      fromURI: _processedPath,
      codec: Codec.pcm16,
      sampleRate: 16000,
      numChannels: 1,
      whenFinished: () {
        _isPlayingProcessed = false;
      },
    );
  }
  
  /// 停止播放处理后的音频
  Future<void> stopPlayingProcessed() async {
    if (!_isPlayingProcessed) return;
    
    await _playerProcessed.stopPlayer();
    _isPlayingProcessed = false;
  }
  
  /// 切换实时降噪模式
  void toggleRealTimeMode() {
    _isRealTimeEnabled = !_isRealTimeEnabled;
  }
  
  /// 释放资源
  Future<void> dispose() async {
    if (_isRecording) {
      await stopRecording();
    }
    
    await _amplitudeSubscription?.cancel();
    await _recorder.dispose();
    
    if (_isPlayerInitialized) {
      await _player.closePlayer();
      _isPlayerInitialized = false;
    }
    
    if (_isPlayerProcessedInitialized) {
      await _playerProcessed.closePlayer();
      _isPlayerProcessedInitialized = false;
    }
  }
}
