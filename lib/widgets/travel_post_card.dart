import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// CONTROLLERS & SERVICES
import 'package:tour/controllers/home_controller.dart';
import 'package:tour/services/audio_service.dart';
import 'package:tour/services/share_service.dart'; // <--- IMPORT NEW SERVICE

// IMPORT THE UI FILE
import 'travel_post_view.dart';

class TravelPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final String postId;
  // Note: removed unused onLikeChanged param for cleaner code
  
  const TravelPostCard({
    super.key,
    required this.post,
    required this.postId,
    required Null Function() onLikeChanged, 
  });

  @override
  State<TravelPostCard> createState() => _TravelPostCardState();
}

class _TravelPostCardState extends State<TravelPostCard> {
  // Logic State
  bool _isSharing = false; // Still needed for loading spinner state
  late bool _isLiked;
  late int _likesCount;
  String? _lastLiker;
  final List<String> _imageUrls = [];

  @override
  void initState() {
    super.initState();
    _extractImageUrls();
    _initializePostData();
  }

  @override
  void didUpdateWidget(covariant TravelPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) {
      _initializePostData();
    }
  }

  // --- INITIALIZATION HELPERS ---
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
    _isLiked = (currentUid != null) ? likesArray.contains(currentUid) : false;
  }

  void _extractImageUrls() {
    _imageUrls.clear();
    // 1. Get list
    if (widget.post['imageUrls'] is List) {
      final List<dynamic> urls = widget.post['imageUrls'] as List<dynamic>;
      _imageUrls.addAll(urls.whereType<String>());
    }
    // 2. Fallback list
    if (widget.post['images'] is List) {
      final List<dynamic> urls = widget.post['images'] as List<dynamic>;
      _imageUrls.addAll(urls.whereType<String>());
    }
    // 3. Single image
    final singleImage = widget.post['image'] as String?;
    if (singleImage != null && singleImage.isNotEmpty && !_imageUrls.contains(singleImage)) {
      _imageUrls.add(singleImage);
    }
  }

  // --- ACTIONS ---

  Future<void> _handleLikePress() async {
    final controller = Provider.of<HomeController>(context, listen: false);

    if (controller.currentUser == null) {
      controller.showLoginPrompt(context, action: 'Liking posts');
      return;
    }

    final myName = controller.currentUser?.displayName ?? 'Someone';

    // Optimistic Update
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        _likesCount++;
        _lastLiker = myName;
      } else {
        _likesCount--;
      }
    });

    await controller.togglePostLike(widget.postId, !_isLiked, myName);
  }

  // ⚡ UPDATED SHARE METHOD: Cleaner & Modular
  Future<void> _handleSharePress() async {
    if (_isSharing) return;

    setState(() => _isSharing = true);

    // Call the Service
    await ShareService.sharePost(
      context: context,
      post: widget.post,
      postId: widget.postId,
      mediaUrls: _imageUrls,
    );

    if (mounted) setState(() => _isSharing = false);
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
    } catch (e) { /* ignore */ }
    return 'Recently';
  }

  @override
  Widget build(BuildContext context) {
    return TravelPostView(
      post: widget.post,
      postId: widget.postId,
      imageUrls: _imageUrls,
      isLiked: _isLiked,
      likesCount: _likesCount,
      lastLiker: _lastLiker,
      isSharing: _isSharing,
      formattedTime: _formatTimestamp(widget.post['createdAt']),
      onLikePressed: _handleLikePress,
      onSharePressed: _handleSharePress, // Points to our simplified method
    );
  }
}