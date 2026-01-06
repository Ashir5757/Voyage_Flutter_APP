import 'dart:ui'; // For Glass effect
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// SERVICES & WIDGETS
// Make sure these paths match your project structure
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

  String _getOptimizedUrl(String originalUrl) {
    if (!originalUrl.contains('cloudinary.com')) return originalUrl;
    if (originalUrl.contains('/upload/')) {
      return originalUrl.replaceFirst('/upload/', '/upload/w_1080,q_auto,f_auto/');
    }
    return originalUrl;
  }

  @override
  Widget build(BuildContext context) {
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
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(liveData),

                  if (liveImageUrls.isNotEmpty) 
                    _buildDynamicMediaLayout(liveImageUrls, liveData, isCurrentPost, audioService),

                  // FOOTER SECTION
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMinimalActions(), // Like Text -> Heart -> Share
                        _buildDescription(liveData), 
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  // --- DYNAMIC MEDIA LAYOUT ---
  Widget _buildDynamicMediaLayout(List<String> imageUrls, Map<String, dynamic> data, bool isCurrentPost, AudioService audioService) {
    Widget buildContent() {
      // 1. Single Media
      if (imageUrls.length == 1) {
        final url = imageUrls.first;
        final bool isVideo = _isVideo(url);
        final bool shouldPlay = _isCardVisible;

        return Stack(
          alignment: Alignment.bottomRight,
          children: [
            isVideo
              ? FeedVideoPlayer(
                  key: ValueKey(url), 
                  videoUrl: url,
                  shouldPlay: shouldPlay, 
                )
              : CachedNetworkImage(
                  key: ValueKey(url),
                  imageUrl: _getOptimizedUrl(url),
                  memCacheWidth: 1080,
                  fit: BoxFit.fitWidth,
                  width: double.infinity,
                  placeholder: (context, url) => Container(height: 300, color: Colors.grey[50]),
                  errorWidget: (context, url, error) => Container(height: 300, color: Colors.grey[200]),
                ),
            
            if (_hasMusic(data))
              _buildGlassAudioTag(data, isCurrentPost, audioService),
          ],
        );
      } 
      
      // 2. Carousel
      else {
        return SizedBox(
          height: 450, 
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
                    return FeedVideoPlayer(key: ValueKey(url), videoUrl: url, shouldPlay: shouldPlay);
                  }
                  return CachedNetworkImage(
                    key: ValueKey(url),
                    imageUrl: _getOptimizedUrl(url),
                    memCacheWidth: 800, 
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (context, url) => Container(color: Colors.grey[100]),
                    errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image)),
                  );
                },
              ),
              
              // Dots Indicator
              Positioned(
                bottom: 12, left: 0, right: 0,
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
                
              if (_hasMusic(data))
                _buildGlassAudioTag(data, isCurrentPost, audioService),
            ],
          ),
        );
      }
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
        minHeight: 250, 
      ),
      child: Container(
        width: double.infinity,
        color: Colors.black, 
        child: buildContent(),
      ),
    );
  }

  bool _hasMusic(Map<String, dynamic> data) {
    return data['musicUrl'] != null && (data['musicUrl'] as String).isNotEmpty;
  }

  // GLASS AUDIO TAG (Bottom Right)
  Widget _buildGlassAudioTag(Map<String, dynamic> data, bool isCurrentPost, AudioService audioService) {
    return Positioned(
      bottom: 12, 
      right: 12,  
      child: GestureDetector(
        onTap: () async {
          final musicUrl = data['musicUrl'] as String;
          if (isCurrentPost) {
            await audioService.togglePlayPause(widget.postId);
          } else {
            await audioService.play(musicUrl, widget.postId);
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4), 
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCurrentPost && audioService.isLoading)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else if (isCurrentPost && audioService.isPlaying)
                    const Icon(Icons.graphic_eq, color: Colors.white, size: 16)
                  else
                    const Icon(Icons.music_note, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 90),
                    child: Text(
                      data['musicTitle'] ?? data['music'] ?? 'Music', 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis, 
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> data) {
    final avatarUrl = data['userPhoto'] as String? ?? 'https://res.cloudinary.com/dseozz7gs/image/upload/v1640995129/default_avatar.jpg';
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey[200],
            backgroundImage: CachedNetworkImageProvider(
              _getOptimizedUrl(avatarUrl),
              maxHeight: 100,
              maxWidth: 100,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['userName'] as String? ?? 'Traveler', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black87)),
                if (data['location'] != null && data['location'].isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 12, color: Colors.blue[600]),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          data['location'], 
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey[400], fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis
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

  // --- MINIMAL ACTIONS (Text -> Heart -> Share) ---
 // --- MINIMAL ACTIONS (Heart -> Liked By Text -> Share) ---
  Widget _buildMinimalActions() {
    return Row(
      children: [
        // 1. Heart Icon (First)
        GestureDetector(
          onTap: widget.onLikePressed,
          child: ScaleTransition(
            scale: _likeScaleAnimation,
            child: Icon(
              widget.isLiked ? Icons.favorite : Icons.favorite_border,
              color: widget.isLiked ? const Color(0xFFFF2E63) : Colors.black87,
              size: 26,
            ),
          ),
        ),

        const SizedBox(width: 8), // Gap between heart and text

        // 2. "Liked by..." Text (Second)
        if (widget.likesCount > 0)
          Expanded( // 'Expanded' ensures text doesn't push the share icon off screen
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                children: [
                  const TextSpan(text: 'Liked by '),
                  TextSpan(
                    text: widget.lastLiker ?? 'Someone',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (widget.likesCount > 1) ...[
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: '${_formatCount(widget.likesCount - 1)} others',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // 3. Spacer (Pushes Share Icon to the far right)
        // If there are no likes, this Spacer still works to push Share to the end.
        if (widget.likesCount == 0) const Spacer(), 

        // 4. Share Icon (Last)
        IconButton(
          onPressed: widget.isSharing ? null : widget.onSharePressed,
          icon: widget.isSharing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                )
              : const Icon(Icons.share_outlined, size: 24, color: Colors.black54),
        ),
      ],
    );
  }

  // --- CLEAN DESCRIPTION ---
  Widget _buildDescription(Map<String, dynamic> data) {
    final description = data['description'] as String? ?? '';
    if (description.isEmpty) return const SizedBox.shrink();
    
    // Check length to decide if "Show more" is needed
    final bool isLong = description.length > 100 || description.split('\n').length > 3;

    return Padding(
      // FIXED: Added horizontal padding so start and end are aligned with margins
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           GestureDetector(
              onTap: () {
                if (isLong) setState(() => _isDescriptionExpanded = !_isDescriptionExpanded);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
                    maxLines: _isDescriptionExpanded ? null : 2,
                    overflow: _isDescriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                  if (isLong)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _isDescriptionExpanded ? 'Show less' : 'Show more',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
           ),
           const SizedBox(height: 8),
           Text(
             widget.formattedTime.toUpperCase(), 
             style: TextStyle(fontSize: 10, color: Colors.grey[400], letterSpacing: 0.5)
           ),
        ],
      ),
    );
  }
  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    double value = count / 1000;
    return (value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1)) + 'k';
  }
}