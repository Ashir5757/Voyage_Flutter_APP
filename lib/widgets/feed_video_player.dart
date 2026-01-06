import 'package:flutter/material.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart'; // v3.0.3
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:tour/services/audio_service.dart';

// FIX: Hide conflicting classes so Flutter uses the ones from cached_video_player_plus
import 'package:video_player/video_player.dart'
    hide VideoProgressIndicator, VideoProgressColors;

class FeedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool shouldPlay;

  const FeedVideoPlayer({
    super.key,
    required this.videoUrl,
    this.shouldPlay = false,
  });

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer>
    with AutomaticKeepAliveClientMixin {
  
  // Controller for v3.0.3
  late CachedVideoPlayerPlusController _controller;

  // UI States
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isMuted = false;
  bool _hasError = false;

  // Slider State
  bool _isDragging = false;
  double _currentSliderValue = 0.0;
  double _totalDuration = 0.0;

  // Animation
  bool _showAnimIcon = false;
  IconData _animIcon = Icons.play_arrow;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reload if URL changes
    if (widget.videoUrl != oldWidget.videoUrl) {
      _disposeController();
      _resetState();
      _initializeVideo();
      return;
    }

    // Handle Play/Pause from Parent (Feed visibility)
    if (_isInitialized && !_hasError) {
      if (widget.shouldPlay && !oldWidget.shouldPlay) {
        _stopBackgroundMusic();
        _controller.play();
      } else if (!widget.shouldPlay && oldWidget.shouldPlay) {
        _controller.pause();
      }
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _resetState() {
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _hasError = false;
        _isBuffering = true;
        _currentSliderValue = 0.0;
        _totalDuration = 0.0;
      });
    }
  }

  void _disposeController() {
    try {
      _controller.removeListener(_onControllerUpdate);
      _controller.dispose();
    } catch (_) {}
  }

  void _stopBackgroundMusic() {
    if (!mounted) return;
    try {
      Provider.of<AudioService>(context, listen: false).stop();
    } catch (_) {}
  }

  String _optimizeCloudinaryUrl(String url) {
    if (url.contains('cloudinary.com') && !url.contains('q_auto')) {
      return url.replaceFirst('/upload/', '/upload/q_auto,vc_auto/');
    }
    return url;
  }

  Future<void> _initializeVideo() async {
    final optimizedUrl = _optimizeCloudinaryUrl(widget.videoUrl);

    // v3.0.3 Syntax: .networkUrl(Uri)
    _controller = CachedVideoPlayerPlusController.networkUrl(
      Uri.parse(optimizedUrl),
      httpHeaders: {},
      invalidateCacheIfOlderThan: const Duration(days: 30),
    );

    _controller.addListener(_onControllerUpdate);

    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      await _controller.setVolume(1.0);

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _hasError = false;
        // Try to get duration immediately
        final duration = _controller.value.duration.inMilliseconds.toDouble();
        _totalDuration = duration > 0 ? duration : 0.0;
      });

      if (widget.shouldPlay) {
        _stopBackgroundMusic();
        _controller.play();
      }
    } catch (e) {
      debugPrint("Video Error: $e");
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _onControllerUpdate() {
    if (!mounted || !_isInitialized) return;

    final value = _controller.value;

    // FIX: Constantly check for duration if we missed it initially
    if (_totalDuration <= 0.0 && value.duration.inMilliseconds > 0) {
      setState(() {
        _totalDuration = value.duration.inMilliseconds.toDouble();
      });
    }

    // Update Slider position only if NOT dragging
    if (!_isDragging) {
      final position = value.position.inMilliseconds.toDouble();
      setState(() {
        _currentSliderValue = position.clamp(0.0, _totalDuration);
        _isPlaying = value.isPlaying;
        _isBuffering = value.isBuffering;
      });
    } else {
      // Just update status if dragging
      setState(() {
        _isPlaying = value.isPlaying;
        _isBuffering = value.isBuffering;
      });
    }
  }

  void _togglePlay() {
    if (!_isInitialized) return;

    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _animIcon = Icons.pause;
      } else {
        _stopBackgroundMusic();
        _controller.play();
        _animIcon = Icons.play_arrow;
      }
      _showAnimIcon = true;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showAnimIcon = false);
    });
  }

  void _toggleMute() {
    if (!_isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  String _getThumbnailUrl(String url) {
    if (url.contains('cloudinary.com')) {
      return url.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.jpg');
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_hasError) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.grey, size: 32),
            SizedBox(height: 8),
            Text('Video unavailable', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(color: Colors.black),

          if (_isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: CachedVideoPlayerPlus(_controller),
                ),
              ),
            ),

          // Thumbnail Logic: Show if loading OR if it's at the very start
          if (!_isInitialized || (_isInitialized && !_isPlaying && _currentSliderValue < 200))
            CachedNetworkImage(
              imageUrl: _getThumbnailUrl(widget.videoUrl),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              memCacheWidth: 600,
              placeholder: (context, url) => Container(color: Colors.black),
              errorWidget: (context, url, error) => Container(color: Colors.black),
            ),

          // Buffering Spinner (YouTube Style)
          if (!_isInitialized || _isBuffering)
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            ),

          // Play/Pause Animation
          if (_showAnimIcon)
            AnimatedOpacity(
              opacity: _showAnimIcon ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                child: Icon(_animIcon, color: Colors.white, size: 40),
              ),
            ),

          // Mute Button
          Positioned(
            bottom: 20, // Moved up slightly to avoid overlap with slider
            right: 16,
            child: GestureDetector(
              onTap: _toggleMute,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                child: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 20),
              ),
            ),
          ),

          // --- FIXED SLIDER ---
          // Always render the container, but only show slider if we have duration
         
        ],
      ),
    );
  }
}