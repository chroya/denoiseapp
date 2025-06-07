import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path_helper;
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';

// WavUtils is no longer needed here as we receive full WAV chunks
// import '../utils/wav_utils.dart';

const int _SAMPLE_RATE = 48000;

class PlaybackService {
  final AudioPlayer _player = AudioPlayer();
  
  // We will no longer manage _isPlaying manually. We rely on player.playing.
  // bool _isPlaying = false; 
  String? _currentPlayingPath;
  
  // For concatenating source
  ConcatenatingAudioSource? _concatenatingSource;
  final List<String> _tempFilePaths = [];
  
  // Callbacks
  Function()? onPlaybackComplete;
  Function()? onStateChanged;
  Function(String)? onError;

  PlaybackService() {
    // This combined stream is the single source of truth for UI updates.
    _player.playerStateStream.listen((state) {
      print("[PlaybackService] Player state changed: ${state.processingState}, playing: ${state.playing}");
      if (state.processingState == ProcessingState.completed || 
          state.processingState == ProcessingState.idle) {
        print("[PlaybackService] Player completed/idle, cleaning up");
        _cleanupAfterStop();
      }
      // Notify the UI that something about the player's state has changed.
      onStateChanged?.call();
    });

    // Listen for player errors
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.loading) {
        print("[PlaybackService] Player is loading...");
      }
    });

    // Add error stream listener
    _player.playbackEventStream.listen((event) {
      print("[PlaybackService] Playback event: $event");
    });
  }

  // Configure audio session for proper audio output
  Future<void> _configureAudioSession() async {
    try {
      print("[PlaybackService] Configuring audio session...");
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      print("[PlaybackService] Audio session configured successfully");
    } catch (e) {
      print("[PlaybackService] Error configuring audio session: $e");
      onError?.call("音频配置失败: $e");
    }
  }

  // The UI will now call this getter.
  bool get isPlaying => _player.playing;
  String? get currentPlayingPath => _currentPlayingPath;

  Future<void> playFile(String path) async {
    print("[PlaybackService] playFile called: $path");
    await _player.stop(); // Ensure player is stopped before starting new playback.
    
    // Configure audio session before playback
    await _configureAudioSession();
    
    _currentPlayingPath = path;
    try {
      print("[PlaybackService] Setting audio source for file: $path");
      await _player.setAudioSource(AudioSource.uri(Uri.file(path)));
      print("[PlaybackService] Starting playback for file: $path");
      await _player.play();
      print("[PlaybackService] Playback started successfully for file: $path");
      
      // Additional verification
      await Future.delayed(Duration(milliseconds: 500));
      print("[PlaybackService] Playback verification - Playing: ${_player.playing}, Position: ${_player.position}, Duration: ${_player.duration}");
      
    } catch (e) {
      print("[PlaybackService] Error playing file: $e");
      onError?.call("播放文件失败: $e");
      await _player.stop();
    }
  }

  /// Plays a stream of WAV audio chunks using a concatenating source.
  StreamSubscription<Uint8List> playWavStream(Stream<Uint8List> wavStream) {
    print("[PlaybackService] playWavStream called");
    _player.stop(); // Clean up any previous state first.
    
    // Configure audio session before playback
    _configureAudioSession();
    
    _currentPlayingPath = "denoised_stream";
    bool hasPlaybackStarted = false;

    final streamSubscription = wavStream.listen(
      (wavChunk) async {
        print("[PlaybackService] Received WAV chunk of size: ${wavChunk.length} bytes");
        try {
          if (!hasPlaybackStarted) {
            print("[PlaybackService] First chunk received, setting up concatenating source");
            hasPlaybackStarted = true;
            _concatenatingSource = ConcatenatingAudioSource(children: []);
            
            final tempFile = await _writeChunkToTempFile(wavChunk);
            print("[PlaybackService] Adding first chunk to concatenating source: ${tempFile.path}");
            await _concatenatingSource!.add(AudioSource.uri(Uri.file(tempFile.path)));
            
            print("[PlaybackService] Setting concatenating source on player");
            await _player.setAudioSource(_concatenatingSource!, preload: true);
            print("[PlaybackService] Concatenating source set up successfully");
            
            print("[PlaybackService] Starting stream playback");
            await _player.play();
            print("[PlaybackService] Stream playback started successfully");
            
            // Additional verification for stream playback
            await Future.delayed(Duration(milliseconds: 500));
            print("[PlaybackService] Stream verification - Playing: ${_player.playing}, Sources: ${_concatenatingSource?.length}");
            
          } else {
            final tempFile = await _writeChunkToTempFile(wavChunk);
            print("[PlaybackService] Adding subsequent chunk to concatenating source: ${tempFile.path}");
            await _concatenatingSource?.add(AudioSource.uri(Uri.file(tempFile.path)));
            print("[PlaybackService] Chunk added successfully");
          }
        } catch (e) {
          print("[PlaybackService] Error handling WAV chunk: $e");
          onError?.call("处理音频数据失败: $e");
          await _player.stop();
        }
      },
      onDone: () {
        print("[PlaybackService] WAV stream done");
        if (!hasPlaybackStarted) {
          print("[PlaybackService] No chunks received, stopping player");
          _player.stop();
        } else {
          print("[PlaybackService] Stream finished, letting player complete naturally");
        }
      },
      onError: (e) {
        print("[PlaybackService] Error in WAV stream: $e");
        onError?.call("音频流错误: $e");
        _player.stop();
      }
    );
    
    return streamSubscription;
  }
  
  Future<File> _writeChunkToTempFile(Uint8List chunk) async {
      final tempDir = await getTemporaryDirectory();
      final fileName = "chunk_${DateTime.now().millisecondsSinceEpoch}.wav";
      final tempFile = File(path_helper.join(tempDir.path, fileName));
      
      print("[PlaybackService] Creating temp file: ${tempFile.path}");
      await tempFile.writeAsBytes(chunk);
      
      // Verify the file was created successfully
      if (await tempFile.exists()) {
        final fileSize = await tempFile.length();
        print("[PlaybackService] Temp file created successfully: ${tempFile.path} (${fileSize} bytes)");
        _tempFilePaths.add(tempFile.path);
        return tempFile;
      } else {
        print("[PlaybackService] ERROR: Failed to create temp file: ${tempFile.path}");
        throw Exception("Failed to create temp file: ${tempFile.path}");
      }
  }

  Future<void> pause() async {
    print("[PlaybackService] pause called");
    await _player.pause();
    // Add a small delay to ensure the pause state is properly registered
    await Future.delayed(Duration(milliseconds: 50));
    print("[PlaybackService] pause completed - Playing: ${_player.playing}");
  }

  Future<void> resume() async {
    print("[PlaybackService] resume called");
    await _player.play();
    // Add a small delay to ensure the play state is properly registered
    await Future.delayed(Duration(milliseconds: 50));
    print("[PlaybackService] resume completed - Playing: ${_player.playing}");
  }

  Future<void> stop() async {
    print("[PlaybackService] stop called");
    await _player.stop();
  }

  void _cleanupAfterStop() {
    if (_currentPlayingPath == null) {
      print("[PlaybackService] Already clean, skipping cleanup");
      return; // Already clean
    }
    
    final wasStreaming = _concatenatingSource != null;
    print("[PlaybackService] Cleaning up after stop (was streaming: $wasStreaming)");
    
    _currentPlayingPath = null;
    _concatenatingSource = null; // This should already be cleared by player.stop()
    
    // Delay temp file cleanup to ensure player is completely done with them
    if (wasStreaming && _tempFilePaths.isNotEmpty) {
      print("[PlaybackService] Delaying temp file cleanup to ensure player is finished");
      Timer(Duration(seconds: 2), () {
        _cleanupTempFiles();
      });
    } else {
      _cleanupTempFiles();
    }

    // Only trigger the specific completion callback if it was a stream
    if (wasStreaming) {
      print("[PlaybackService] Triggering completion callback");
      onPlaybackComplete?.call();
    }
  }

  void _cleanupTempFiles() {
    print("[PlaybackService] Cleaning up ${_tempFilePaths.length} temp files");
    for (final path in _tempFilePaths) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          print("[PlaybackService] Deleting temp file: $path");
          file.deleteSync();
          print("[PlaybackService] Temp file deleted successfully: $path");
        } else {
          print("[PlaybackService] Temp file already gone: $path");
        }
      } catch (e) {
        print("[PlaybackService] Error deleting temp chunk file $path: $e");
      }
    }
    _tempFilePaths.clear();
    print("[PlaybackService] Temp file cleanup completed");
  }

  Future<void> dispose() async {
    print("[PlaybackService] dispose called");
    await _player.dispose();
  }
} 