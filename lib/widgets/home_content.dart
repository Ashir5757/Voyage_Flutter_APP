import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// CONTROLLERS & SERVICES
import 'package:tour/controllers/home_controller.dart';
import 'package:tour/services/audio_service.dart';

// NEW MODULAR WIDGETS
import 'package:tour/widgets/hero_header.dart';
import 'package:tour/widgets/travel_post_card.dart';

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
  // Local keys to prevent "Duplicate GlobalKey" crash
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
          // 1. HERO BACKGROUND (Extracted)
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
                child: const RepaintBoundary(child: HeroHeader()),
              );
            },
          ),
      
          // 2. MAIN FEED
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    widget.controller.handleAutoPlay(context, audioService, _localPostKeys);
                  }
                });
              }
              return false;
            },
            child: _buildMainContent(context, audioService),
          ),
      
          // 3. TOP BAR (Search & Profile)
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

        widget.controller.updateVisiblePosts(displayDocs);

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final doc = displayDocs[index];
              final post = doc.data() as Map<String, dynamic>;

              if (!_localPostKeys.containsKey(doc.id)) {
                _localPostKeys[doc.id] = GlobalKey();
              }

             return Container(
                key: _localPostKeys[doc.id], 
                child: TravelPostCard(
                  post: post,
                  postId: doc.id,
                  onLikeChanged: () {},
                  // onCommentPressed: () {
                  //    if (widget.controller.currentUser == null) {
                  //       widget.controller.showLoginPrompt(context, action: 'Commenting');
                  //    }
                  // },
                ),
              );
            },
            childCount: displayDocs.length,
          ),
        );
      },
    );
  }

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
}