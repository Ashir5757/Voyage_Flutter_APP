import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FeedVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const FeedVideoPlayer({
    super.key, 
    required this.videoUrl,
  });

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    if (_controller != null) return; // Already initialized

    // 1. Create Controller
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    
    try {
      await _controller!.initialize();
      setState(() {
        _isInitialized = true;
        _isPlaying = true;
      });
      await _controller!.play();
      await _controller!.setLooping(true);
    } catch (e) {
      debugPrint("Video Error: $e");
      setState(() => _hasError = true);
    }
  }

  void _togglePlay() {
    if (!_isInitialized) {
      // First tap: Initialize and Play
      _initializeVideo();
    } else {
      // Subsequent taps: Toggle Play/Pause
      setState(() {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
          _isPlaying = false;
        } else {
          _controller!.play();
          _isPlaying = true;
        }
      });
    }
  }

  // Cloudinary Trick: Change extension to .jpg to get a thumbnail!
  // This works because Cloudinary automatically generates thumbnails for videos.
  String _getThumbnailUrl(String videoUrl) {
    if (videoUrl.contains('cloudinary.com')) {
      // Replace file extension (e.g., .mp4) with .jpg
      return videoUrl.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.jpg');
    }
    return videoUrl; // Fallback if not Cloudinary
  }

  @override
  Widget build(BuildContext context) {
    // 1. Calculate Aspect Ratio (Default to 1:1 square if not loaded)
    final double aspectRatio = _isInitialized 
        ? _controller!.value.aspectRatio 
        : 1.0; 

    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        color: Colors.black,
        // Constraints: Don't let it get too tall (like 9:16 stories) or too short
        constraints: const BoxConstraints(
          maxHeight: 500, // Max height similar to Instagram 4:5
          minHeight: 250,
        ),
        child: Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // A. THE VIDEO (If initialized)
                if (_isInitialized)
                  VideoPlayer(_controller!)
                
                // B. THE THUMBNAIL (If NOT initialized or Loading)
                else 
                  CachedNetworkImage(
                    imageUrl: _getThumbnailUrl(widget.videoUrl),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
                  ),

                // C. PLAY BUTTON OVERLAY
                if (!_isPlaying && !_isInitialized)
                   Container(
                     padding: const EdgeInsets.all(12),
                     decoration: BoxDecoration(
                       color: Colors.black.withOpacity(0.5),
                       shape: BoxShape.circle,
                     ),
                     child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                   ),
                
                // D. LOADING SPINNER (While initializing)
                if (_controller != null && !_isInitialized && !_hasError)
                   const CircularProgressIndicator(color: Colors.white),
                  
                // E. ERROR ICON
                if (_hasError)
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, color: Colors.white),
                      SizedBox(height: 8),
                      Text("Video unavailable", style: TextStyle(color: Colors.white, fontSize: 12))
                    ],
                  ),
                  
                // F. SOUND ICON (Optional visual cue)
                if (_isInitialized)
                  Positioned(
                    bottom: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _controller!.value.volume > 0 ? Icons.volume_up : Icons.volume_off,
                        color: Colors.white, 
                        size: 16
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}