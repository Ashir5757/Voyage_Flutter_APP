// lib/widgets/travel_post_widget.dart - REVISED MUSIC AND ACTIONS
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:tour/services/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart'; // Import for sharing

// NOTE: Ensure your AudioService class handles stopping previous tracks
// when a new 'play' call is made, or we must explicitly stop it here.

class TravelPostWidget extends StatefulWidget {
  final Map<String, dynamic> post;
  final String postId;
  final VoidCallback? onLikeChanged;
  final VoidCallback? onCommentPressed;

  const TravelPostWidget({
    super.key,
    required this.post,
    required this.postId,
    this.onLikeChanged,
    this.onCommentPressed,
  });

  @override
  State<TravelPostWidget> createState() => _TravelPostWidgetState();
}

class _TravelPostWidgetState extends State<TravelPostWidget> {
  final AudioService _audioService = AudioService();
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;
  bool _isPlayingThisPost = false;
  
  // Cloudinary instance - configure with your credentials
  final CloudinaryPublic _cloudinary = CloudinaryPublic(
    'dseozz7gs',  // Your Cloudinary cloud name
    'voyage_upload_preset', // Your upload preset name
  );

  // Music variables
  String? _musicUrl;
  String? _musicTitle;
  String? _musicArtist;
  bool _isMusicLoading = false;

  // Post data variables
  late bool _isLiked;
  late int _likes;
  late int _comments;

 @override
void initState() {
  super.initState();
  _initializePostData();
  _initializeMusic();
  
  // --- REVISED AUDIO STATE LISTENER ---
  _audioService.player.playerStateStream.listen((state) {
    if (!mounted) return;
    
    final isPlayingCurrent = _audioService.currentPostId == widget.postId && 
                            _audioService.isPlaying;

    // We only call setState if the status relevant to THIS post has changed
    if (_isPlayingThisPost != isPlayingCurrent) {
      setState(() {
        _isPlayingThisPost = isPlayingCurrent;
      });
    }
  });
  // ------------------------------------
}

  void _initializePostData() {
    _isLiked = (widget.post['isLiked'] as bool?) ?? false;
    _likes = (widget.post['likes'] as int?) ?? 0;
    _comments = (widget.post['comments'] as int?) ?? 0;
  }

  void _initializeMusic() {
    _musicUrl = widget.post['musicUrl'] as String?;
    _musicTitle = widget.post['musicTitle'] as String?;
    _musicArtist = widget.post['musicArtist'] as String?;
    
    if ((_musicTitle == null || _musicTitle!.isEmpty) && 
        widget.post['music'] is String) {
      _musicTitle = widget.post['music'] as String;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    setState(() {
      _isLiked = !_isLiked;
      _likes += _isLiked ? 1 : -1;
    });
    
    if (widget.onLikeChanged != null) {
      widget.onLikeChanged!();
    }
  }

// --- REVISED MUSIC LOGIC ---
  Future<void> _playMusic() async {
    if (_musicUrl == null || _musicUrl!.isEmpty) {
      print('No music URL available for this post');
      _showMusicErrorSnackbar();
      return;
    }

    setState(() => _isMusicLoading = true);
    
    // Check if this is a Jamendo URL
    final isJamendoUrl = _musicUrl!.contains('jamendo.com') || 
                        _musicUrl!.contains('jamendo.net');
    
    try {
      if (isJamendoUrl) {
        await _handleJamendoPlayback();
      } else {
        // Direct playback
        await _audioService.play(_musicUrl!, widget.postId);
      }
    } catch (e) {
      print('Error playing music: $e');
      _showMusicErrorSnackbar();
    } finally {
      if (mounted) {
        setState(() => _isMusicLoading = false);
      }
    }
  }

  Future<void> _handleJamendoPlayback() async {
    // Note: Loading state is already set in _playMusic()
    try {
      await _audioService.play(_musicUrl!, widget.postId);
    } catch (e) {
      print('Direct Jamendo playback failed: $e');
      
      final directUrl = await _getJamendoDirectStream(_musicUrl!);
      if (directUrl != null) {
        await _audioService.play(directUrl, widget.postId);
      } else {
        _showMusicErrorSnackbar();
      }
    }
  }

  Future<String?> _getJamendoDirectStream(String jamendoUrl) async {
    try {
      final uri = Uri.parse(jamendoUrl);
      final trackId = uri.queryParameters['trackid'];
      
      if (trackId != null) {
        return 'https://prod-1.storage.jamendo.com/download/track/$trackId/mp31/';
      }
    } catch (e) {
      print('Error parsing Jamendo URL: $e');
    }
    return null;
  }
// -----------------------------


  void _showMusicErrorSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cannot play music: ${_musicTitle ?? 'Unknown track'}'),
        backgroundColor: Colors.red,
      ),
    );
  }

// --- NEW SHARE LOGIC ---
  void _sharePost() {
    final String shareText = 
      'Check out this amazing travel post by ${widget.post['userName'] ?? 'a traveler'}! '
      'Location: ${widget.post['location'] ?? 'Unknown'}. '
      'Description: "${widget.post['description'] ?? ''}"';
      
    // You would typically include a direct app link or deep link here
    Share.share(shareText); 
  }
// -----------------------

  @override
  Widget build(BuildContext context) {
    // Get images from Firestore - using 'imageUrls' field
    final List<String> images = _getImagesFromPost();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildImageCarousel(images),
          // --- ACTIONS CALL UPDATED ---
          _buildActions(),
          // ----------------------------
          _buildDescription(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    // ... (No changes here)
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage(
              widget.post['userPhoto'] as String? ?? 
              'https://res.cloudinary.com/dseozz7gs/image/upload/v1640995129/default_avatar.jpg'
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.post['userName'] as String? ?? 'Traveler',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 13, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text(
                      widget.post['location'] as String? ?? 'Unknown Location',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getImagesFromPost() {
    // ... (No changes here)
    // First try to get images from 'imageUrls' (Cloudinary array)
    if (widget.post['imageUrls'] is List) {
      final List<dynamic> urls = widget.post['imageUrls'] as List<dynamic>;
      return urls.whereType<String>().toList();
    }
    
    // Fallback to 'images' field
    if (widget.post['images'] is List) {
      final List<dynamic> urls = widget.post['images'] as List<dynamic>;
      return urls.whereType<String>().toList();
    }
    
    // Fallback to single 'image' field
    final singleImage = widget.post['image'] as String?;
    if (singleImage != null && singleImage.isNotEmpty) {
      return [singleImage];
    }
    
    // Default fallback
    return ['images/alps.jpg'];
  }

  Widget _buildImageCarousel(List<String> images) {
    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          // Image Carousel
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
            },
            itemBuilder: (context, imgIndex) {
              final imageUrl = images[imgIndex];
              
              // Apply Cloudinary transformations if it's a Cloudinary URL
              String displayUrl = imageUrl;
              if (imageUrl.contains('cloudinary.com')) {
                displayUrl = _optimizeCloudinaryUrl(imageUrl);
              }
              
              return _buildNetworkImage(displayUrl);
            },
          ),

          // Pagination dots
          if (images.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (index) {
                  final isActive = index == _currentImageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 8 : 6,
                    height: isActive ? 8 : 6,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : Colors.white54,
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),

          // Music Overlay
          Positioned(
            bottom: 20,
            right: 12,
            child: GestureDetector(
              onTap: () async {
                if (_isMusicLoading) return;
                
                // If the current music playing belongs to THIS post, toggle it.
                if (_audioService.currentPostId == widget.postId && _musicUrl != null && _musicUrl!.isNotEmpty) {
                  await _audioService.togglePlayPause(widget.postId);
                } else {
                  // If no music is playing, or if music from a different post is playing,
                  // stop the old one (which should happen implicitly in AudioService.play)
                  // and start playing this one.
                  await _playMusic();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(180),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isMusicLoading)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    else
                      // Icon showing music note when paused/stopped
                      Icon(
                        _isPlayingThisPost ? Icons.pause_circle_filled : Icons.music_note,
                        color: Colors.white,
                        size: 18,
                      ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 90,
                      child: Text(
                        _musicTitle ?? 'No Music',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Icon showing play/pause arrow
                    Icon(
                      _isPlayingThisPost ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _optimizeCloudinaryUrl(String originalUrl) {
    // ... (No changes here)
    // Apply Cloudinary transformations for optimal display
    if (originalUrl.contains('/upload/')) {
      return originalUrl.replaceFirst(
        '/upload/',
        '/upload/c_fill,h_400,w_400,q_auto,f_auto/'
      );
    }
    return originalUrl;
  }

  Widget _buildNetworkImage(String url) {
    // ... (No changes here)
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                : null,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
          ),
        );
      },
    );
  }

  // --- REVISED ACTIONS WIDGET (Added Share) ---
  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          // Like button
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _toggleLike,
            icon: Icon(
              _isLiked ? Icons.favorite : Icons.favorite_border,
              color: _isLiked ? Colors.red : Colors.grey[700],
              size: 26,
            ),
          ),
          Text('$_likes', style: const TextStyle(fontWeight: FontWeight.w600)),
          
          const SizedBox(width: 14),
          
          // Comment button
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: widget.onCommentPressed,
            icon: Icon(Icons.comment_outlined, size: 26, color: Colors.grey[700]),
          ),
          Text('$_comments', style: const TextStyle(fontWeight: FontWeight.w600)),
          
          const Spacer(),
          
          // Share button
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _sharePost, // Calls the implemented share function
            icon: Icon(Icons.share_outlined, size: 24, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
// ------------------------------------------------

  Widget _buildDescription() {
    // ... (No changes here)
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.post['description'] as String? ?? '',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            _formatTimestamp(widget.post['createdAt']),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    // ... (No changes here)
    if (timestamp == null) return 'Recently';
    
    try {
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();
        final now = DateTime.now();
        final difference = now.difference(date);
        
        if (difference.inDays > 0) {
          return '${difference.inDays} days ago';
        } else if (difference.inHours > 0) {
          return '${difference.inHours} hours ago';
        } else if (difference.inMinutes > 0) {
          return '${difference.inMinutes} minutes ago';
        } else {
          return 'Just now';
        }
      }
      
      // Try parsing as DateTime string
      if (timestamp is String) {
        final date = DateTime.parse(timestamp);
        final now = DateTime.now();
        final difference = now.difference(date);
        
        if (difference.inDays > 0) {
          return '${difference.inDays} days ago';
        } else if (difference.inHours > 0) {
          return '${difference.inHours} hours ago';
        }
      }
    } catch (e) {
      print('Error formatting timestamp: $e');
    }
    
    return 'Recently';
  }
}