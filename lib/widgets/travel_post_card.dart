import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:cross_file/cross_file.dart';

// CONTROLLERS & SERVICES
import 'package:tour/controllers/home_controller.dart';
import 'package:tour/services/audio_service.dart';
import 'package:tour/widgets/feed_video_player.dart';

class TravelPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final String postId;
  final VoidCallback? onLikeChanged;
  final VoidCallback? onCommentPressed;

  const TravelPostCard({
    super.key,
    required this.post,
    required this.postId,
    this.onLikeChanged,
    this.onCommentPressed,
  });

  @override
  State<TravelPostCard> createState() => _TravelPostCardState();
}

class _TravelPostCardState extends State<TravelPostCard> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  
  late AnimationController _likeAnimController;
  late Animation<double> _likeScaleAnimation;

  bool _isSharing = false;
  int _currentImageIndex = 0;
  bool _isDescriptionExpanded = false;
  
  late bool _isLiked;
  late int _likesCount;
  String? _lastLiker;
  final List<String> _imageUrls = [];

  @override
  void initState() {
    super.initState();
    _extractImageUrls();
    _initializePostData();

    _likeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    _likeScaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _likeAnimController, curve: Curves.easeInOut),
    );
  }

  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) {
      double value = count / 1000;
      return (value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1)) + 'k';
    }
    double value = count / 1000000;
    return (value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1)) + 'M';
  }

  @override
  void didUpdateWidget(covariant TravelPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) {
      _initializePostData();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _likeAnimController.dispose();
    super.dispose();
  }

  void _initializePostData() {
    final controller = Provider.of<HomeController>(context, listen: false);
    final currentUid = controller.currentUser?.uid;

    var likesField = widget.post['likes'];
    List<dynamic> likesArray = [];

    if (likesField is List) {
      likesArray = likesField;
      _likesCount = widget.post['likesCount'] ?? likesArray.length;
    } else if (likesField is int) {
      _likesCount = likesField;
      likesArray = [];
    } else {
      _likesCount = 0;
      likesArray = [];
    }
    
    _lastLiker = widget.post['lastLiker'] as String?;

    if (currentUid != null) {
      _isLiked = likesArray.contains(currentUid);
    } else {
      _isLiked = false;
    }
  }

  void _extractImageUrls() {
    _imageUrls.clear();
    if (widget.post['imageUrls'] is List) {
      final List<dynamic> urls = widget.post['imageUrls'] as List<dynamic>;
      _imageUrls.addAll(urls.whereType<String>());
    }
    if (widget.post['images'] is List) {
      final List<dynamic> urls = widget.post['images'] as List<dynamic>;
      _imageUrls.addAll(urls.whereType<String>());
    }
    final singleImage = widget.post['image'] as String?;
    if (singleImage != null && singleImage.isNotEmpty && !_imageUrls.contains(singleImage)) {
      _imageUrls.add(singleImage);
    }
  }

  bool _isVideo(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi') || lower.contains('/video/upload/');
  }

  Future<void> _handleLikePress() async {
    final controller = Provider.of<HomeController>(context, listen: false);

    if (controller.currentUser == null) {
      controller.showLoginPrompt(context, action: 'Liking posts');
      return;
    }

    final myName = controller.currentUser?.displayName ?? 'Someone';

    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        _likesCount++;
        _lastLiker = myName; 
        _likeAnimController.forward().then((_) => _likeAnimController.reverse());
      } else {
        _likesCount--;
      }
    });

    await controller.togglePostLike(widget.postId, !_isLiked, myName); 
  }

  Future<void> _sharePost() async {
    if (_isSharing) return;

    setState(() => _isSharing = true);

    try {
      final userName = widget.post['userName'] ?? 'a traveler';
      final location = widget.post['location'] != null ? '📍 ${widget.post['location']}' : '';
      final description = widget.post['description'] ?? '';

      final String shareText = '$description\n\n👤 Posted by: $userName\n$location';
      await Clipboard.setData(ClipboardData(text: shareText));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Caption copied! Paste it if missing.'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      XFile? fileToShare;
      if (_imageUrls.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final imageUrl = _imageUrls.first; 
        try {
          final response = await http.get(Uri.parse(imageUrl));
          if (response.statusCode == 200) {
            final file = File('${tempDir.path}/voyage_share_${widget.postId}.jpg');
            await file.writeAsBytes(response.bodyBytes);
            fileToShare = XFile(file.path);
          }
        } catch (e) {
          debugPrint('Image download failed: $e');
        }
      }

      if (fileToShare != null) {
        await Share.shareXFiles([fileToShare], text: shareText);
      } else {
        await Share.share(shareText);
      }
    } catch (e) {
      debugPrint("Share failed: $e");
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  String? _getMusicTitle() {
    String? title = widget.post['musicTitle'] as String?;
    if ((title == null || title.isEmpty) && widget.post['music'] is String) {
      title = widget.post['music'] as String;
    }
    return title;
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Recently';
    try {
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();
        final now = DateTime.now();
        final difference = now.difference(date);
        if (difference.inDays > 0) return '${difference.inDays} days ago';
        if (difference.inHours > 0) return '${difference.inHours} hours ago';
        return 'Just now';
      }
    } catch (e) {
      // ignore error
    }
    return 'Recently';
  }

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioService>(context, listen: true);
    final isCurrentPost = audioService.currentPostId == widget.postId;
    final musicTitle = _getMusicTitle();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_imageUrls.isNotEmpty) _buildMediaCarousel(isCurrentPost, audioService, musicTitle),
          _buildActions(isCurrentPost, audioService),
          _buildLikedByText(), 
          _buildDescription(),
        ],
      ),
    );
  }

  Widget _buildLikedByText() {
    if (_likesCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black, fontSize: 13),
          children: [
            const WidgetSpan(
              child: Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.favorite, size: 14, color: Colors.black),
              ),
              alignment: PlaceholderAlignment.middle,
            ),
            const TextSpan(text: 'Liked by '),
            TextSpan(text: _lastLiker ?? 'Someone', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_likesCount > 1) ...[
              const TextSpan(text: ' and '),
              TextSpan(text: '${_formatCount(_likesCount - 1)} others', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: CachedNetworkImageProvider(
              widget.post['userPhoto'] as String? ?? 'https://res.cloudinary.com/dseozz7gs/image/upload/v1640995129/default_avatar.jpg'
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.post['userName'] as String? ?? 'Traveler', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 13, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text(widget.post['location'] as String? ?? 'Unknown Location', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaCarousel(bool isCurrentPost, AudioService audioService, String? musicTitle) {
    // CURRENT: AspectRatio 1.0 (Square). 
    // FUTURE: You can change this to be dynamic based on image/video dimensions.
    return AspectRatio(
      aspectRatio: 1.0, 
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _imageUrls.length,
            onPageChanged: (index) => setState(() => _currentImageIndex = index),
            itemBuilder: (context, imgIndex) {
              final url = _imageUrls[imgIndex];
              if (_isVideo(url)) {
                return FeedVideoPlayer(
                  videoUrl: url,
                  shouldPlay: isCurrentPost && audioService.isPlaying,
                );
              }
              return CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) => Container(color: Colors.grey[200]),
                errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image)),
              );
            },
          ),
          if (_imageUrls.length > 1)
            Positioned(
              bottom: 10, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_imageUrls.length, (index) {
                  final isActive = index == _currentImageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 8 : 6,
                    height: isActive ? 8 : 6,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : Colors.white54,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                    ),
                  );
                }),
              ),
            ),
          if (widget.post['musicUrl'] != null && (widget.post['musicUrl'] as String).isNotEmpty)
            Positioned(
              bottom: 16, right: 12,
              child: GestureDetector(
                onTap: () async {
                  final musicUrl = widget.post['musicUrl'] as String;
                  if (audioService.currentPostId == widget.postId) {
                    await audioService.togglePlayPause(widget.postId);
                  } else {
                    await audioService.play(musicUrl, widget.postId);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCurrentPost && audioService.isLoading)
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      else
                        Icon(isCurrentPost && audioService.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(musicTitle ?? 'Music', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                      ),
                      if (isCurrentPost && audioService.isPlaying) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.music_note, color: Colors.white70, size: 10),
                      ]
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(bool isCurrentPost, AudioService audioService) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: _handleLikePress,
            child: ScaleTransition(
              scale: _likeScaleAnimation,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, color: _isLiked ? Colors.red : Colors.grey[700], size: 28),
              ),
            ),
          ),
          Text(_formatCount(_likesCount), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const Spacer(),
          IconButton(
            onPressed: _isSharing ? null : _sharePost,
            icon: _isSharing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)) : Icon(Icons.share_outlined, size: 24, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    final description = widget.post['description'] as String? ?? '';
    if (description.isEmpty) return const SizedBox.shrink();

    final bool isLong = description.length > 60 || description.contains('\n');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topLeft,
            child: GestureDetector(
              onTap: () {
                if (isLong) setState(() => _isDescriptionExpanded = !_isDescriptionExpanded);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: const TextStyle(fontSize: 14, height: 1.3),
                    maxLines: _isDescriptionExpanded ? null : 1,
                    overflow: _isDescriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                  if (isLong)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(_isDescriptionExpanded ? 'Show less' : 'Read more', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(_formatTimestamp(widget.post['createdAt']), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ],
      ),
    );
  }
}