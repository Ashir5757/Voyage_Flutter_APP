import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

// PAGE IMPORTS
import 'package:tour/pages/add_post_page.dart';
import 'package:tour/pages/profile_page.dart';

// SERVICE IMPORTS
import 'package:tour/services/audio_service.dart';

class HomeController extends ChangeNotifier {
  // --- CONTROLLERS & SERVICES ---
  final ScrollController scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- STATE VARIABLES ---
  double scrollOffset = 0.0;
  int selectedIndex = 0;
  bool showUserDropdown = false;
  User? _currentUser;

  // --- FEED DATA ---
  final Map<String, GlobalKey> postKeys = {}; // Stores position of every post
  List<DocumentSnapshot> visiblePosts = [];   // Stores the actual post data

  // --- SEARCH VARIABLES ---
  bool isSearching = false;
  List<DocumentSnapshot> searchResults = [];

  // --- CONSTRUCTOR ---
  HomeController() {
    scrollController.addListener(_scrollListener);
   
    // Listen for auth changes (Sign In, Sign Out, Profile Update)
    _auth.userChanges().listen((User? user) {
      _currentUser = user;
      notifyListeners();
    });
    
    _currentUser = _auth.currentUser;
  }

  User? get currentUser => _currentUser;

  @override
  void dispose() {
    scrollController.removeListener(_scrollListener); 
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    scrollOffset = scrollController.offset;
  }
  
  void onItemTapped(int index) {
    selectedIndex = index;
    notifyListeners();
  }
  
  // --- DROPDOWN LOGIC ---
  void toggleUserDropdown() {
    showUserDropdown = !showUserDropdown;
    notifyListeners();
  }
  
  void closeUserDropdown() {
    if (showUserDropdown) {
      showUserDropdown = false;
      notifyListeners();
    }
  }

  // --- NAVIGATION (With Music Stopping) ---
  
  void navigateToProfile(BuildContext context) {
    Provider.of<AudioService>(context, listen: false).stop();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UserProfilePage()),
    );
  }

  void navigateToCreatePost(BuildContext context) {
    Provider.of<AudioService>(context, listen: false).stop();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddPostPage()),
    );
  }

  void navigateToLogin(BuildContext context) {
    // Assuming you have named routes set up in main.dart
    Navigator.pushNamed(context, '/login');
  }
  
  Future<void> logout(BuildContext context) async {
    try {
      Provider.of<AudioService>(context, listen: false).stop();
      await _auth.signOut();
      showUserDropdown = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  // --- SEARCH FUNCTIONALITY ---

  void onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      isSearching = false;
      searchResults = [];
      notifyListeners();
      return;
    }

    isSearching = true;
    final lowerQuery = query.toLowerCase();

    // Filter visible posts locally to save reads
    searchResults = visiblePosts.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      
      final location = (data['location'] ?? '').toString().toLowerCase();
      final description = (data['description'] ?? '').toString().toLowerCase();
      final userName = (data['userName'] ?? '').toString().toLowerCase();

      return location.contains(lowerQuery) || 
             description.contains(lowerQuery) || 
             userName.contains(lowerQuery);
    }).toList();

    notifyListeners();
  }

  void clearSearch() {
    searchController.clear();
    isSearching = false;
    searchResults = [];
    FocusManager.instance.primaryFocus?.unfocus();
    notifyListeners();
  }
  
  void searchDestinations() {
    // Optional: Add extra logic here if "Enter" is pressed
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // --- AUTO-PLAY LOGIC ---

  void handleAutoPlay(BuildContext context, AudioService audioService) {
    // Stop if searching or menu is open
    if (showUserDropdown || searchController.text.isNotEmpty) {
      audioService.stop();
      return;
    }

    String? bestPostId;
    double minDistance = double.infinity;
    
    // Get screen metrics
    final screenHeight = MediaQuery.of(context).size.height;
    final screenCenter = screenHeight / 2;

    // Find the post closest to the center of the screen
    for (var doc in visiblePosts) {
      final postId = doc.id;
      final key = postKeys[postId];

      if (key != null && key.currentContext != null) {
        final RenderBox box = key.currentContext!.findRenderObject() as RenderBox;
        final position = box.localToGlobal(Offset.zero);
        final postCenter = position.dy + (box.size.height / 2);
        final distance = (postCenter - screenCenter).abs();

        // Threshold: Post must be within 40% of screen center to activate
        if (distance < minDistance && distance < (screenHeight * 0.4)) { 
          minDistance = distance;
          bestPostId = postId;
        }
      }
    }

    // Play the best candidate
    if (bestPostId != null) {
       if (audioService.currentPostId == bestPostId && audioService.isPlaying) {
         return; // Already playing this one
       }

       final postSnapshot = visiblePosts.firstWhere((d) => d.id == bestPostId);
       final postData = postSnapshot.data() as Map<String, dynamic>;
       
       String? musicUrl = postData['musicUrl'] ?? postData['music'];
       
       if (musicUrl != null && musicUrl.isNotEmpty) {
         audioService.play(musicUrl, bestPostId);
       } else {
         audioService.stop(); 
       }
    }
  }

  // --- LIKE LOGIC ---

  Future<void> togglePostLike(String postId, bool currentLikeStatus, String userName) async {
    final user = _currentUser;
    if (user == null) return;

    final docRef = FirebaseFirestore.instance.collection('posts').doc(postId);

    try {
      if (currentLikeStatus) {
        // UNLIKE
        await docRef.update({
          'likes': FieldValue.arrayRemove([user.uid]),
          'likesCount': FieldValue.increment(-1),
        });
      } else {
        // LIKE
        await docRef.update({
          'likes': FieldValue.arrayUnion([user.uid]),
          'likesCount': FieldValue.increment(1),
          'lastLiker': userName,
        });
      }
    } catch (e) {
      debugPrint("Error toggling like: $e");
    }
  }

  // --- DIALOGS ---

  void showLoginPrompt(BuildContext context, {String action = ''}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline, size: 32, color: Colors.deepPurple),
            ),
            const SizedBox(height: 16),
            Text(
              action.isNotEmpty ? '$action requires login' : 'Sign in required',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Create an account to share your travel stories, like posts, and connect with other travelers.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/register');
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Colors.deepPurple),
                ),
                child: const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.deepPurple)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continue as Guest', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}