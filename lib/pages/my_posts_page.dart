import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import 'package:tour/controllers/home_controller.dart';
import 'package:tour/widgets/guest_view.dart';
import 'package:tour/pages/edit_post_page.dart'; 
// IMPORT THE NEW SERVICE
import 'package:tour/services/post_service.dart'; 

class MyPostsPage extends StatelessWidget {
  const MyPostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final controller = Provider.of<HomeController>(context, listen: false);

    if (user == null) {
      return GuestView(
        title: "Travel Journal Locked",
        message: "Log in to access your personal travel history.",
        onLoginPressed: () => controller.navigateToLogin(context),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50], 
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('My Travel Journal', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildUserPostsList(user.uid),
    );
  }

  Widget _buildUserPostsList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.menu_book, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('Journal Empty', style: TextStyle(fontSize: 20, color: Colors.grey[800])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final postData = doc.data() as Map<String, dynamic>;
            
            return _JournalEntryCard(
              docId: doc.id,
              data: postData,
            );
          },
        );
      },
    );
  }
}

// --- UPDATED CARD WIDGET ---
class _JournalEntryCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;

  // Instantiate the service
  final PostService _postService = PostService();

  _JournalEntryCard({
    super.key,
    required this.docId,
    required this.data,
  });

  String _getRawMediaUrl() {
    if (data['imageUrls'] is List && (data['imageUrls'] as List).isNotEmpty) {
      return (data['imageUrls'] as List).first;
    }
    if (data['image'] != null && data['image'].toString().isNotEmpty) {
      return data['image'];
    }
    return ''; 
  }

  String _getThumbnail(String url) {
    if (url.isEmpty) return '';
    final lower = url.toLowerCase();
    bool isVideo = lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi') || lower.contains('/video/upload/');
    if (isVideo) {
      return url.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.jpg');
    }
    return url; 
  }

  String _formatDate() {
    final timestamp = data['createdAt'];
    if (timestamp is Timestamp) {
      return DateFormat('MMM d, yyyy').format(timestamp.toDate());
    }
    return 'Unknown Date';
  }

  // --- UPDATED DELETE LOGIC ---
  Future<void> _confirmDelete(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Memory?"),
        content: const Text("This will remove the post and permanently delete all associated photos/videos. Are you sure?"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              
              // Show loading snackbar
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Deleting post and media..."), duration: Duration(seconds: 1)),
                );
              }

              try {
                // 1. Gather all URLs to delete
                List<String> urlsToDelete = [];
                if (data['imageUrls'] is List) {
                   urlsToDelete = List<String>.from(data['imageUrls']);
                } else if (data['image'] != null) {
                   urlsToDelete.add(data['image']);
                }

                // 2. CALL THE NEW SERVICE
                await _postService.deletePost(
                  postId: docId, 
                  imageUrls: urlsToDelete,
                  userId: data['userId'], // Pass User ID to update count
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Post deleted successfully"), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawUrl = _getRawMediaUrl();
    final thumbnail = _getThumbnail(rawUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.white,
          child: InkWell(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // THUMBNAIL
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: thumbnail.isNotEmpty
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: thumbnail,
                                  width: 80, height: 80, fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                              if (rawUrl != thumbnail) 
                                Container(
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                                )
                            ],
                          )
                        : const Icon(Icons.image, color: Colors.grey),
                  ),
                  const SizedBox(width: 16),

                  // TEXT
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['location'] ?? 'Unknown Location',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(_formatDate(), style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        const SizedBox(height: 8),
                        Text(
                          data['description'] ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.2),
                        ),
                      ],
                    ),
                  ),

                  // BUTTONS
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20, color: Colors.blueAccent),
                        tooltip: 'Edit',
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditPostPage(
                                postId: docId,
                                currentData: data,
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                        onPressed: () => _confirmDelete(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}