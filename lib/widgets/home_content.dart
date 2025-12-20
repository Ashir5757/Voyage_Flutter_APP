import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tour/controllers/home_controller.dart';
import 'package:tour/services/audio_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

// VIDEO PLAYER IMPORT
import 'package:tour/widgets/feed_video_player.dart'; 

class HomeContent extends StatefulWidget {
  final HomeController controller;
  final TextEditingController searchController;
  final int selectedIndex;
  final bool showUserDropdown;
  final VoidCallback onSearchSubmitted;
  final ValueChanged<int> onNavItemTapped;
  final VoidCallback onUserProfileTap;
  final VoidCallback onCloseDropdown;
  final VoidCallback onLoginTap;
  final VoidCallback onProfileTap;
  final VoidCallback onLogoutTap;
  final VoidCallback onCreatePostTap;

  const HomeContent({
    super.key,
    required this.controller,
    required this.searchController,
    required this.selectedIndex,
    required this.showUserDropdown,
    required this.onSearchSubmitted,
    required this.onNavItemTapped,
    required this.onUserProfileTap,
    required this.onCloseDropdown,
    required this.onLoginTap,
    required this.onProfileTap,
    required this.onLogoutTap,
    required this.onCreatePostTap,
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  // LOCAL KEYS to prevent "Duplicate GlobalKey" crash
  final Map<String, GlobalKey> _localPostKeys = {};

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioService>(context, listen: false);

    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Stack(
        children: [
          // 1. HERO BACKGROUND
          AnimatedBuilder(
            animation: widget.controller.scrollController,
            builder: (context, _) {
              double offset = 0.0;
              try {
                if (widget.controller.scrollController.hasClients) {
                  offset = widget.controller.scrollController.offset;
                }
              } catch (e) {
                offset = 0.0;
              }
              double parallaxOffset = (offset * 0.4).clamp(0.0, 350.0);
              return Positioned(
                top: -parallaxOffset,
                left: 0, right: 0, height: 350,
                child: RepaintBoundary(child: _buildHeroContent()),
              );
            },
          ),
      
          // 2. MAIN FEED
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    // PASS LOCAL KEYS TO CONTROLLER
                    widget.controller.handleAutoPlay(context, audioService, _localPostKeys);
                  }
                });
              }
              return false;
            },
            child: _buildMainContent(context, audioService),
          ),
      
          // 3. TOP BAR
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(child: _buildFloatingSearchBar()),
                      const SizedBox(width: 12),
                      
                      if (widget.controller.isSearching)
                        GestureDetector(
                          onTap: () => widget.controller.clearSearch(),
                          child: Container(
                            width: 50, height: 50,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Icons.close, color: Colors.white),
                          ),
                        )
                      else
                        _buildUserProfileButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
      
          if (widget.showUserDropdown) _buildUserDropdownOverlay(),
        ],
      ),
    );
  }

  Widget _buildFloatingSearchBar() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3), 
        borderRadius: BorderRadius.circular(25),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextField(
            controller: widget.searchController,
            onChanged: (val) {
              widget.controller.onSearchChanged(val);
            },
            style: const TextStyle(color: Colors.white, fontSize: 15),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: 'Search destinations...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              prefixIcon: const Icon(Icons.search, color: Colors.white, size: 20),
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              filled: false,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, AudioService audioService) {
    return CustomScrollView(
      controller: widget.controller.scrollController,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 320)),
        _buildPostsList(context, audioService),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildPostsList(BuildContext context, AudioService audioService) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }

        final allDocs = snapshot.data!.docs;
        List<DocumentSnapshot> displayDocs = allDocs;

        if (widget.controller.isSearching && widget.searchController.text.isNotEmpty) {
           final query = widget.searchController.text.toLowerCase().trim();
           displayDocs = allDocs.where((doc) {
             final data = doc.data() as Map<String, dynamic>;
             final loc = (data['location'] ?? '').toString().toLowerCase();
             final desc = (data['description'] ?? '').toString().toLowerCase();
             final user = (data['userName'] ?? '').toString().toLowerCase();
             return loc.contains(query) || desc.contains(query) || user.contains(query);
           }).toList();
        }

        if (displayDocs.isEmpty) {
          return SliverToBoxAdapter(
            child: Container(
              height: 200,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, size: 50, color: Colors.grey),
                  const SizedBox(height: 10),
                  Text('No matching posts found', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ],
              ),
            ),
          );
        }

        // Safe update for controller
        widget.controller.updateVisiblePosts(displayDocs);

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final doc = displayDocs[index];
              final post = doc.data() as Map<String, dynamic>;

              // GENERATE LOCAL KEYS
              if (!_localPostKeys.containsKey(doc.id)) {
                _localPostKeys[doc.id] = GlobalKey();
              }

             return Container(
                key: _localPostKeys[doc.id], 
                child: TravelPostCard(
                  post: post,
                  postId: doc.id,
                  onLikeChanged: () {},
                  onCommentPressed: () {
                     if (widget.controller.currentUser == null) {
                        widget.controller.showLoginPrompt(context, action: 'Commenting');
                     }
                  },
                ),
              );
            },
            childCount: displayDocs.length,
          ),
        );
      },
    );
  }

  // --- BUTTONS & HELPERS ---
  Widget _buildUserProfileButton() {
    final user = widget.controller.currentUser;
    if (user == null) {
      return GestureDetector(
        onTap: widget.onLoginTap, 
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3), 
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Icon(Icons.login, color: Colors.white, size: 20),
                   SizedBox(width: 8),
                   Text('Sign In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: widget.onUserProfileTap,
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: ClipOval(
          child: (user.photoURL != null && user.photoURL!.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: user.photoURL!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey[300], child: const Icon(Icons.person, color: Colors.grey)),
                  errorWidget: (context, url, error) => Container(color: Colors.grey[300], child: const Icon(Icons.error, color: Colors.grey)),
                )
              : Container(color: Colors.grey[300], child: const Icon(Icons.person, color: Colors.grey, size: 30)),
        ),
      ),
    );
  }

  Widget _buildUserDropdownOverlay() {
     return GestureDetector(
      onTap: widget.onCloseDropdown,
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.transparent)),
          Positioned(
            top: 65, right: 16,
            child: GestureDetector(
              onTap: () {},
              child: Material(
                elevation: 4, borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 220,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.deepPurple[50], borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundImage: widget.controller.currentUser!.photoURL != null
                                  ? NetworkImage(widget.controller.currentUser!.photoURL!)
                                  : const AssetImage('images/boy.jpg') as ImageProvider,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.controller.currentUser!.displayName ?? 'Traveler', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text(widget.controller.currentUser!.email ?? 'user@example.com', style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(color: Colors.transparent, child: InkWell(onTap: widget.onProfileTap, child: Container(padding: const EdgeInsets.all(16), child: const Row(children: [Icon(Icons.person, color: Colors.deepPurple, size: 22), SizedBox(width: 12), Text('My Profile', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w600, fontSize: 15))])))),
                      Material(color: Colors.transparent, child: InkWell(onTap: widget.onLogoutTap, child: Container(padding: const EdgeInsets.all(16), child: const Row(children: [Icon(Icons.logout, color: Colors.red, size: 22), SizedBox(width: 12), Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 15))])))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroContent() {
    return SizedBox(
      height: 400, 
      width: double.infinity,
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
              ),
            ),
          ),
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
            ),
          ),
          Positioned(
            top: 100, left: -50,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.03)),
            ),
          ),
          Positioned(
            bottom: -50, right: -20,
            child: Container(
              width: 150, height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.tealAccent.withOpacity(0.2), Colors.transparent],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.only(bottom: 60, left: 24, right: 24),
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.travel_explore, color: Colors.tealAccent, size: 40),
                const SizedBox(height: 16),
                const Text('Voyage', style: TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.bold, fontFamily: 'DancingScript', shadows: [Shadow(blurRadius: 10.0, color: Colors.black45, offset: Offset(2.0, 2.0))])),
                const Text('Explore the world with us', style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 1.2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- POST CARD ---
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
  int _comments = 0; 
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
      CurvedAnimation(
        parent: _likeAnimController,
        curve: Curves.easeInOut,
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

    _comments = (widget.post['comments'] as int?) ?? 0;
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

      final String shareText = 
          '$description\n\n'
          '👤 Posted by: $userName\n'
          '$location';

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
        if (difference.inMinutes > 0) return '${difference.inMinutes} minutes ago';
        return 'Just now';
      }
      if (timestamp is String) {
        final date = DateTime.parse(timestamp);
        final now = DateTime.now();
        final difference = now.difference(date);
        if (difference.inDays > 0) return '${difference.inDays} days ago';
        if (difference.inHours > 0) return '${difference.inHours} hours ago';
      }
    } catch (e) {
      print('Error formatting timestamp: $e');
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
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_imageUrls.isNotEmpty) _buildImageCarousel(isCurrentPost, audioService, musicTitle),
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
            TextSpan(
              text: _lastLiker ?? 'Someone',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_likesCount > 1) ...[
              const TextSpan(text: ' and '),
              TextSpan(
                text: '${_formatCount(_likesCount - 1)} others',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
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
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 13, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text(
                      widget.post['location'] as String? ?? 'Unknown Location',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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

  Widget _buildImageCarousel(bool isCurrentPost, AudioService audioService, String? musicTitle) {
    return SizedBox(
      height: 300, 
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _imageUrls.length,
            onPageChanged: (index) {
              setState(() => _currentImageIndex = index);
            },
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
              bottom: 16, 
              right: 12,
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
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, 
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white)
                          ),
                        )
                      else
                        Icon(
                          isCurrentPost && audioService.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white, size: 18,
                        ),
                        
                      const SizedBox(width: 6),
                      
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          musicTitle ?? 'Music',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white, 
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
                child: Icon(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _isLiked ? Colors.red : Colors.grey[700],
                  size: 28,
                ),
              ),
            ),
          ),
          
          Text(
            _formatCount(_likesCount), 
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)
          ),
          
          const SizedBox(width: 10),
          
          const Spacer(),
          
          IconButton(
            onPressed: _isSharing ? null : _sharePost,
            icon: _isSharing
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                  )
                : Icon(Icons.share_outlined, size: 24, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  // ✅ FIXED: "Read More" with smooth size animation
  Widget _buildDescription() {
    final description = widget.post['description'] as String? ?? '';
    
    if (description.isEmpty) return const SizedBox.shrink();

    // Heuristic: Text is "long" if > 60 chars or has a new line
    final bool isLong = description.length > 60 || description.contains('\n');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AnimatedSize handles the "box changing size" smoothly
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topLeft,
            child: GestureDetector(
              onTap: () {
                if (isLong) {
                  setState(() {
                    _isDescriptionExpanded = !_isDescriptionExpanded;
                  });
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: const TextStyle(fontSize: 14, height: 1.3),
                    // If expanded, show all (null). If collapsed, show 1 line.
                    maxLines: _isDescriptionExpanded ? null : 1,
                    overflow: _isDescriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                  
                  // The "Read more" / "Show less" button
                  if (isLong)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        _isDescriptionExpanded ? 'Show less' : 'Read more',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 6),
          
          // Timestamp
          Text(
            _formatTimestamp(widget.post['createdAt']),
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}