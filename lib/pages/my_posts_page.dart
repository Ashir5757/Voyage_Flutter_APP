import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:tour/controllers/home_controller.dart';
import 'package:tour/widgets/guest_view.dart';
import 'package:tour/widgets/home_content.dart';
import 'package:tour/widgets/guest_view.dart';
// CHECK THIS IMPORT: Point this to where your TravelPostCard file actually is
 

class MyPostsPage extends StatelessWidget {
  const MyPostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Get the current user status immediately
    final user = FirebaseAuth.instance.currentUser;
    // Get the controller for login actions
    final controller = Provider.of<HomeController>(context, listen: false);

    if (user == null) {
      return GuestView(
        title: "Travel Journal Locked",
        message: "Log in to access your personal travel history and edit your past adventures.",
        onLoginPressed: () {
           controller.navigateToLogin(context);
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      
      // 1. APP BAR: Always visible so the Back Arrow works
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'My Travel Journal',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),

     
    );
  }

  // --- VIEW 2: LOGGED IN USER ---
  Widget _buildUserPostsList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: uid) // Ensure your database uses 'userId'
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Error
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        final docs = snapshot.data?.docs ?? [];

        // Empty State (Logged in but no posts)
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_camera_back, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No memories yet',
                  style: TextStyle(fontSize: 20, color: Colors.grey[800], fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your travel journal is empty.',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        // List of Posts
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final postData = doc.data() as Map<String, dynamic>;
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TravelPostCard(
                post: postData,
                postId: doc.id,
              ),
            );
          },
        );
      },
    );
  }
}