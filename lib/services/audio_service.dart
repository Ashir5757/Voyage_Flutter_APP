import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart'; // 1. Import Audio Session

class AudioService extends ChangeNotifier with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  String? _currentPostId;
  bool _isPlaying = false;
  bool _isLoading = false;

  String? get currentPostId => _currentPostId;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;

  AudioService() {
    WidgetsBinding.instance.addObserver(this);
    _initAudioSession(); // 2. Initialize Session
    _setupListeners();
  }

  // 3. OPTIMIZATION: Configure System Audio
  // This ensures your app interacts correctly with Spotify, Phone Calls, etc.
  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    
    // Handle unplugging headphones (Stop music)
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(0.5); // Lower volume for notification
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            stop(); // Stop for phone call
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(1.0); // Restore volume
            break;
          case AudioInterruptionType.pause:
            // Do not auto-resume (standard UX)
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      stop(); 
    }
  }

  void _setupListeners() {
    _player.playerStateStream.listen((state) {
      final wasPlaying = _isPlaying;
      _isPlaying = state.playing;
      
      _isLoading = state.processingState == ProcessingState.loading ||
                   state.processingState == ProcessingState.buffering;
      
      if (wasPlaying != _isPlaying || _isLoading) {
        notifyListeners();
      }
      
      // Auto-stop when song finishes
      if (state.processingState == ProcessingState.completed) {
        stop();
      }
    });

    _player.playbackEventStream.listen((event) {}, onError: (error) {
      debugPrint('Audio error: $error');
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> play(String url, String postId, {bool forceRestart = false}) async {
    try {
      // A. If same song is paused, just resume (Instant)
      if (_currentPostId == postId && !forceRestart) {
        if (!_isPlaying) {
          await _player.play();
        }
        return;
      }

      // B. Stop previous song cleanly
      if (_currentPostId != null && _currentPostId != postId) {
        await _player.stop(); // Don't call stop() to avoid notifying listeners twice unnecessarily
      }

      _currentPostId = postId;
      _isLoading = true;
      notifyListeners();

      // 4. THE ULTIMATE OPTIMIZATION: Caching
      // Instead of setUrl, we use LockCachingAudioSource.
      // This downloads the MP3 to a temp file while playing. 
      // Next time you play it? INSTANT load from disk.
      
      // Note: We handle Cloudinary optimization here too if needed, 
      // but usually audio files don't need resizing like images.
      
      try {
        final audioSource = LockCachingAudioSource(Uri.parse(url));
        await _player.setAudioSource(audioSource);
        await _player.play();
      } catch (e) {
         // Fallback to standard stream if caching fails (e.g. storage permission issue)
         debugPrint("Caching failed, falling back to stream: $e");
         await _player.setUrl(url);
         await _player.play();
      }
      
    } catch (e) {
      debugPrint('Error playing audio: $e');
      _isLoading = false;
      _currentPostId = null;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero); // Reset position
    _currentPostId = null;
    _isPlaying = false;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> togglePlayPause(String postId) async {
    if (_currentPostId != postId) return;

    if (_isPlaying) {
      await pause();
    } else {
      await _player.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }
}