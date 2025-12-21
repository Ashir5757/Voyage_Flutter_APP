import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:tour/services/audio_service.dart';
import 'package:tour/widgets/home_content.dart';
import 'package:tour/widgets/travel_post_card.dart'; // Imports TravelPostCard

class PostDetailPage extends StatelessWidget {
  final String postId;

  const PostDetailPage({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    // 1. WRAP SCAFFOLD IN POPSCOPE
    return PopScope(
      canPop: false, // Handle pop manually
      onPopInvoked: (didPop) async {
        if (didPop) return;

        // STOP MUSIC ON SYSTEM BACK BUTTON
        Provider.of<AudioService>(context, listen: false).stop();

        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text('Travel Story', style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () {
              // STOP MUSIC ON APP BAR BACK BUTTON
              Provider.of<AudioService>(context, listen: false).stop();
              Navigator.pop(context);
            },
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('posts')
              .doc(postId)
              .snapshots(),
          builder: (context, snapshot) {
            // 1. Loading State
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // 2. Error/Not Found State
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Post not found or deleted'),
                  ],
                ),
              );
            }

            // 3. Success State - Show the Card
            final post = snapshot.data!.data() as Map<String, dynamic>;
  
            return SingleChildScrollView(
              padding: const EdgeInsets.only(top: 12, bottom: 20),
              child: TravelPostCard(
                post: post,
                postId: postId,
                // We pass empty functions because we are just viewing
                onLikeChanged: () {}, 
                onCommentPressed: () {},
              ),
            );
          },
        ),
      ),
    );
  }
}