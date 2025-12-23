import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tour/services/storage_service.dart';

class PostService {
  final StorageService _storage = CloudinaryStorageService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Master function to clean up everything related to a post
  Future<void> deletePost({
    required String postId, 
    required List<String> imageUrls,
    String? userId, // Optional: if you want to decrement user's post count
  }) async {
    try {
      // 1. DELETE MEDIA FROM CLOUDINARY
      // We use Future.wait to delete all images in parallel (much faster than a loop)
      if (imageUrls.isNotEmpty) {
        print("🗑️ Deleting ${imageUrls.length} files from Cloudinary...");
        await Future.wait(
          imageUrls.map((url) => _storage.deleteImage(url))
        );
      }

      // 2. DELETE POST FROM FIRESTORE
      print("🗑️ Deleting Firestore document: $postId");
      await _firestore.collection('posts').doc(postId).delete();

      // 3. (Optional) DECREMENT USER POST COUNT
      if (userId != null) {
        await _firestore.collection('users').doc(userId).update({
          'postsCount': FieldValue.increment(-1),
        });
      }
      
    } catch (e) {
      print("❌ Error deleting post: $e");
      rethrow; // Pass error back to UI to show Snackbar
    }
  }
}