// lib/services/audio_service.dart - COMPLETELY FIXED
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  String? _currentPostId;
  bool _isPlaying = false;
  
  // Getters
  String? get currentPostId => _currentPostId;
  bool get isPlaying => _isPlaying;
  AudioPlayer get player => _player; // Keep for backward compatibility
  
  AudioService() {
    _player.playerStateStream.listen((state) {
      final wasPlaying = _isPlaying;
      _isPlaying = state.playing;
      
      // Update playing state
      if (wasPlaying != _isPlaying) {
        notifyListeners();
      }
      
      // Handle completion
      if (state.processingState == ProcessingState.completed) {
        _isPlaying = false;
        _currentPostId = null;
        notifyListeners();
      }
    });
    
    // Handle errors
    _player.playbackEventStream.listen((event) {
      if (event.processingState == ProcessingState.idle && _currentPostId != null) {
        _isPlaying = false;
        _currentPostId = null;
        notifyListeners();
      }
    }, onError: (error) {
      _isPlaying = false;
      _currentPostId = null;
      notifyListeners();
    });
  }
  
  Future<void> play(String url, String postId) async {
    try {
      // If already playing this post, do nothing
      if (_currentPostId == postId && _isPlaying) {
        return;
      }
      
      // Stop current if playing different post
      if (_currentPostId != null && _currentPostId != postId) {
        await _player.stop();
        _isPlaying = false;
      }
      
      // Set new source if needed
      _currentPostId = postId;
      
      // Check if we need to load new source
      bool needsNewSource = true;
      if (_player.audioSource != null) {
        try {
          final currentUri = (_player.audioSource as UriAudioSource).uri.toString();
          needsNewSource = currentUri != url;
        } catch (_) {
          needsNewSource = true;
        }
      }
      
      if (needsNewSource) {
        if (url.contains('jamendo.com') || url.contains('jamendo.net')) {
          await _handleJamendoAudio(url);
        } else {
          await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
        }
      }
      
      await _player.play();
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      _isPlaying = false;
      _currentPostId = null;
      notifyListeners();
      rethrow;
    }
  }
  
  Future<void> _handleJamendoAudio(String url) async {
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
    } catch (e) {
      // Try direct stream
      final uri = Uri.parse(url);
      final trackId = uri.queryParameters['trackid'];
      
      if (trackId != null) {
        final directUrl = 'https://prod-1.storage.jamendo.com/download/track/$trackId/mp31/';
        await _player.setAudioSource(AudioSource.uri(Uri.parse(directUrl)));
      } else {
        throw Exception('Invalid Jamendo URL');
      }
    }
  }
  
  Future<void> togglePlayPause(String postId) async {
    if (_currentPostId == postId) {
      if (_isPlaying) {
        await pause();
      } else {
        await _player.play();
        _isPlaying = true;
        notifyListeners();
      }
    } else {
      // Different post - will be handled by play()
    }
  }
  
  Future<void> pause() async {
    if (_isPlaying) {
      await _player.pause();
      _isPlaying = false;
      notifyListeners();
    }
  }
  
  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
    _currentPostId = null;
    notifyListeners();
  }
  
  Future<void> disposePlayer() async {
    await _player.dispose();
  }
  
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}