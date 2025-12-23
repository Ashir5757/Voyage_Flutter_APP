import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:tour/services/audio_service.dart';

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

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  late VideoPlayerController _controller;
  
  bool _isInitialized = false;
  bool _isMuted = false;
  bool _hasError = false;

  // Animation States
  bool _showAnimIcon = false;
  IconData _animIcon = Icons.play_arrow;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 1. Handle URL Changes (Recycling views)
    if (widget.videoUrl != oldWidget.videoUrl) {
      _disposeController();
      setState(() {
        _isInitialized = false;
        _hasError = false;
      });
      _initializeVideo();     
      return;
    }
    
    // 2. Handle Play/Pause Triggers from VisibilityDetector
    if (!_hasError && _isInitialized) {
       if (widget.shouldPlay && !oldWidget.shouldPlay) {
         _stopBackgroundMusic();
         _controller.play();
       }
       if (!widget.shouldPlay && oldWidget.shouldPlay) {
         _controller.pause();
       }
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    try {
      _controller.dispose();
    } catch (e) {
      debugPrint("Error disposing controller: $e");
    }
  }

  void _stopBackgroundMusic() {
    Provider.of<AudioService>(context, listen: false).stop();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));

    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
        if (widget.shouldPlay) {
          _stopBackgroundMusic();
          _controller.play();
        }
      }
    } catch (e) {
      debugPrint("Video Error: $e");
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  // --- ACTIONS ---

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

    // Hide the icon after 1 second
    Future.delayed(const Duration(milliseconds: 1000), () {
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

  // Optimized Thumbnail Logic
  // (Faster than video_thumbnail package for network urls)
  String _getThumbnailUrl(String videoUrl) {
    if (videoUrl.contains('cloudinary.com')) {
      // Replaces .mp4 with .jpg to get the auto-generated thumbnail from server
      return videoUrl.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.jpg');
    }
    return videoUrl; 
  }

  // --- BUILDERS ---

  @override
  Widget build(BuildContext context) {
    // 1. Error State
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.grey, size: 30),
              SizedBox(height: 8),
              Text("Media unavailable", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    // 2. Loading State (Show Thumbnail)
    if (!_isInitialized) {
      return Stack(
        alignment: Alignment.center,
        children: [
          CachedNetworkImage(
            imageUrl: _getThumbnailUrl(widget.videoUrl),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: 600, // Memory optimization
            errorWidget: (c, u, e) => Container(color: Colors.black),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), shape: BoxShape.circle),
            child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          ),
        ],
      );
    }

    // 3. Player State
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // A. The Actual Video
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            ),
          ),

          // B. Gradient Overlay (Bottom) for better text visibility
          Positioned(
            bottom: 0, left: 0, right: 0,
            height: 80,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                ),
              ),
            ),
          ),

          // C. Animated Play/Pause Icon (Center)
          if (_showAnimIcon)
            AnimatedOpacity(
              opacity: _showAnimIcon ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(_animIcon, color: Colors.white, size: 40),
              ),
            ),

          // D. Mute Button (Bottom Right)
          Positioned(
            bottom: 16,
            right: 16,
            child: GestureDetector(
              onTap: _toggleMute,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isMuted || _controller.value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),

          // E. Progress Bar (Very Bottom)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SizedBox(
              height: 4, // Sleek thin bar
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                padding: EdgeInsets.zero,
                colors: VideoProgressColors(
                  playedColor: const Color(0xFFFF2E63), // Voyage Brand Color?
                  bufferedColor: Colors.white.withOpacity(0.3),
                  backgroundColor: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}