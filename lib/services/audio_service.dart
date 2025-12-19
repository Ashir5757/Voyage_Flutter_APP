import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // Needed for AppLifecycleState
import 'package:just_audio/just_audio.dart';

// 1. Add "with WidgetsBindingObserver"
class AudioService extends ChangeNotifier with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  String? _currentPostId;
  bool _isPlaying = false;
  bool _isLoading = false;

  String? get currentPostId => _currentPostId;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;

  AudioService() {
    // 2. Register this service to listen to App Lifecycle events
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
  }

  // 3. This function runs automatically when the App is minimized/closed
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // If the app goes to background (paused) or is closed (detached)
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      debugPrint("App backgrounded: Auto-stopping music.");
      stop(); // Stop the music immediately
    }
  }

  void _setupListeners() {
    _player.playerStateStream.listen((state) {
      final wasPlaying = _isPlaying;
      _isPlaying = state.playing;
      
      // Update loading state
      _isLoading = state.processingState == ProcessingState.loading ||
                   state.processingState == ProcessingState.buffering;
      
      if (wasPlaying != _isPlaying || state.processingState == ProcessingState.loading) {
        notifyListeners();
      }
    });

    // Handle errors
    _player.playbackEventStream.listen((event) {}, onError: (error) {
      debugPrint('Audio error: $error');
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> play(String url, String postId, {bool forceRestart = false}) async {
    try {
      if (_currentPostId == postId && !forceRestart) {
        if (!_isPlaying) {
          await _player.play();
        }
        return;
      }

      if (_currentPostId != null && _currentPostId != postId) {
        await stop();
      }

      _currentPostId = postId;
      _isLoading = true;
      notifyListeners();

      await _player.setUrl(url);
      await _player.play();
      
    } catch (e) {
      debugPrint('Error playing audio: $e');
      _isLoading = false;
      _currentPostId = null;
      notifyListeners();
      // Only rethrow if you want to handle it in UI, otherwise just logging is safer
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
      notifyListeners();
    } catch (e) {
      debugPrint('Error pausing audio: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      _currentPostId = null;
      _isPlaying = false;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }

  Future<void> togglePlayPause(String postId) async {
    if (_currentPostId != postId) {
      return;
    }

    try {
      if (_isPlaying) {
        await pause();
      } else {
        await _player.play();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error toggling play/pause: $e');
    }
  }

  static Future<String?> getJamendoDirectUrl(String jamendoUrl) async {
    try {
      final uri = Uri.parse(jamendoUrl);
      final trackId = uri.queryParameters['trackid'];
      
      if (trackId != null) {
        return 'https://prod-1.storage.jamendo.com/download/track/$trackId/mp31/';
      }
    } catch (e) {
      debugPrint('Error parsing Jamendo URL: $e');
    }
    return null;
  }

  @override
  void dispose() {
    // 4. Clean up the observer when the service is destroyed
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }
}