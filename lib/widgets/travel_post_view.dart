import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// SERVICES & WIDGETS
import 'package:tour/services/audio_service.dart';
import 'package:tour/widgets/feed_video_player.dart';

class TravelPostView extends StatefulWidget {
  final Map<String, dynamic> post;
  final String postId;
  final List<String> imageUrls;
  final bool isLiked;
  final int likesCount;
  final String? lastLiker;
  final bool isSharing;
  final String formattedTime;
  final VoidCallback onLikePressed;
  final VoidCallback onSharePressed;

  const TravelPostView({
    super.key,
    required this.post,
    required this.postId,
    required this.imageUrls,
    required this.isLiked,
    required this.likesCount,
    this.lastLiker,
    required this.isSharing,
    required this.formattedTime,
    required this.onLikePressed,
    required this.onSharePressed,
  });

  @override
  State<TravelPostView> createState() => _TravelPostViewState();
}

class _TravelPostViewState extends State<TravelPostView> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late AnimationController _likeAnimController;
  late Animation<double> _likeScaleAnimation;
  
  int _currentImageIndex = 0;
  bool _isDescriptionExpanded = false;
  bool _isCardVisible = false;

  @override
  void initState() {
    super.initState();
    _likeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _likeScaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _likeAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _likeAnimController.dispose();
    super.dispose();
  }

  bool _isVideo(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') || 
           lower.endsWith('.mov') || 
           lower.contains('/video/upload/'); 
  }

  List<String> _getLiveImages(Map<String, dynamic> data) {
    if (data['imageUrls'] is List) {
      return List<String>.from(data['imageUrls']);
    } else if (data['image'] != null) {
      return [data['image']];
    }
    return [];
  }

  // 🚀 OPTIMIZATION 1: Cloudinary Smart URL
  // This modifies the URL to ask Cloudinary for a smaller, optimized image
  String _getOptimizedUrl(String originalUrl) {
    if (!originalUrl.contains('cloudinary.com')) return originalUrl;
    
    // Inject optimizations: 
    // w_800: Resize to 800px width (plenty for phones)
    // q_auto: Automatic quality compression
    // f_auto: Use best file format (WebP/AVIF)
    if (originalUrl.contains('/upload/')) {
      return originalUrl.replaceFirst('/upload/', '/upload/w_800,q_auto,f_auto/');
    }
    return originalUrl;
  }

  @override
  Widget build(BuildContext context) {
    // We use RepaintBoundary here to isolate this card from the rest of the list
    // This stops the whole list from repainting when one heart animates.
    return RepaintBoundary(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('posts').doc(widget.postId).snapshots(),
        builder: (context, snapshot) {
          
          Map<String, dynamic> liveData;
          List<String> liveImageUrls;

          if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
            liveData = snapshot.data!.data() as Map<String, dynamic>;
            liveImageUrls = _getLiveImages(liveData);
          } else {
            liveData = widget.post;
            liveImageUrls = widget.imageUrls;
          }

          final audioService = Provider.of<AudioService>(context, listen: true);
          final isCurrentPost = audioService.currentPostId == widget.postId;

          return VisibilityDetector(
            key: Key(widget.postId),
            onVisibilityChanged: (info) {
              final bool isVisible = info.visibleFraction > 0.6;
              if (isVisible != _isCardVisible) {
                setState(() => _isCardVisible = isVisible);
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(liveData),
                  if (liveImageUrls.isNotEmpty) 
                    _buildMediaCarousel(liveImageUrls, liveData, isCurrentPost, audioService),
                  _buildActions(),
                  _buildLikedByText(), 
                  _buildDescription(liveData),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> data) {
    // Optimize Avatar Image too
    final avatarUrl = data['userPhoto'] as String? ?? 'https://res.cloudinary.com/dseozz7gs/image/upload/v1640995129/default_avatar.jpg';
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: CachedNetworkImageProvider(
              _getOptimizedUrl(avatarUrl), // Optimize avatar
              maxHeight: 100, // MemCache for avatar
              maxWidth: 100,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['userName'] as String? ?? 'Traveler', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 13, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text(data['location'] as String? ?? 'Unknown Location', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaCarousel(List<String> imageUrls, Map<String, dynamic> data, bool isCurrentPost, AudioService audioService) {
    return AspectRatio(
      aspectRatio: 1.0, 
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: imageUrls.length,
            onPageChanged: (index) => setState(() => _currentImageIndex = index),
            itemBuilder: (context, imgIndex) {
              final url = imageUrls[imgIndex];
              
              if (_isVideo(url)) {
                final bool shouldPlay = _isCardVisible && (_currentImageIndex == imgIndex);
                return FeedVideoPlayer(
                  key: ValueKey(url), 
                  videoUrl: url,
                  shouldPlay: shouldPlay, 
                );
              }
              
              // 🚀 OPTIMIZATION 2: CachedNetworkImage Tuning
              return CachedNetworkImage(
                key: ValueKey(url),
                imageUrl: _getOptimizedUrl(url), // Get smaller file from server
                
                // 🚀 OPTIMIZATION 3: RAM Compression
                // This decodes the image to a specific size in memory. 
                // 1080 is good for high quality phones, 720 is faster.
                memCacheWidth: 800, 
                
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) => Container(color: Colors.grey[100]),
                errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image)),
                fadeInDuration: const Duration(milliseconds: 200), // Smoother appearance
              );
            },
          ),
          
          if (imageUrls.length > 1)
            Positioned(
              bottom: 10, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(imageUrls.length, (index) {
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
            
          if (data['musicUrl'] != null && (data['musicUrl'] as String).isNotEmpty)
            Positioned(
              bottom: 16, right: 12,
              child: GestureDetector(
                onTap: () async {
                  final musicUrl = data['musicUrl'] as String;
                  if (isCurrentPost) {
                    await audioService.togglePlayPause(widget.postId);
                  } else {
                    await audioService.play(musicUrl, widget.postId);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCurrentPost && audioService.isLoading)
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      else if (isCurrentPost && audioService.isPlaying)
                        const Icon(Icons.graphic_eq, color: Colors.white, size: 20)
                      else
                        const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          data['musicTitle'] ?? data['music'] ?? 'Music', 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis, 
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)
                        ),
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

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onLikePressed,
            child: ScaleTransition(
              scale: _likeScaleAnimation,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(widget.isLiked ? Icons.favorite : Icons.favorite_border, color: widget.isLiked ? Colors.red : Colors.grey[700], size: 28),
              ),
            ),
          ),
          Text(_formatCount(widget.likesCount), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const Spacer(),
          IconButton(
            onPressed: widget.isSharing ? null : widget.onSharePressed,
            icon: widget.isSharing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)) : Icon(Icons.share_outlined, size: 24, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDescription(Map<String, dynamic> data) {
    final description = data['description'] as String? ?? '';
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
          Text(widget.formattedTime, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ],
      ),
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
  
  Widget _buildLikedByText() {
    if (widget.likesCount == 0) return const SizedBox.shrink();
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
            TextSpan(text: widget.lastLiker ?? 'Someone', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (widget.likesCount > 1) ...[
              const TextSpan(text: ' and '),
              TextSpan(text: '${_formatCount(widget.likesCount - 1)} others', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }
}