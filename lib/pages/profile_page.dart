import 'dart:io';
import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:provider/provider.dart'; 
import 'package:tour/services/audio_service.dart';
import 'package:tour/pages/my_posts_page.dart';
import 'package:tour/pages/post_detail_page.dart';
import 'package:tour/controllers/home_controller.dart';
import 'package:tour/widgets/guest_view.dart'; // Needed for navigation logic

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  User? _currentUser;
  
  String _displayName = '';
  String _bio = '';
  String _photoUrl = '';
  int _postsCount = 0;
  
  bool _isLoading = true;
  bool _isUploading = false;
  
  // Cloudinary Config
  final String _cloudName = 'dseozz7gs'; 
  final String _uploadPreset = 'voyage_profile_upload';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    final user = _auth.currentUser;
    
    if (user != null) {
      _currentUser = user;
      _displayName = user.displayName ?? 'Traveler';
      _photoUrl = user.photoURL ?? '';
      
      try {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          if (mounted) {
            setState(() {
              _displayName = data['displayName'] as String? ?? _displayName;
              _bio = data['bio'] as String? ?? '';
              _postsCount = data['postsCount'] as int? ?? 0;
              
              final cloudinaryUrl = data['cloudinaryPhotoUrl'] as String?;
              if (cloudinaryUrl != null && cloudinaryUrl.isNotEmpty) {
                _photoUrl = cloudinaryUrl;
              }
            });
            _nameController.text = _displayName;
            _bioController.text = _bio;
          }
        }
      } catch (e) {
        debugPrint("Error loading user data: $e");
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // --- ACTIONS ---

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.purple[50], shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt, color: Colors.purple),
              ),
              title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(context);
                final image = await _picker.pickImage(source: ImageSource.camera, maxWidth: 800, imageQuality: 85);
                if (image != null) await _uploadToCloudinary(File(image.path));
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
                child: const Icon(Icons.photo_library, color: Colors.blue),
              ),
              title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(context);
                final image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
                if (image != null) await _uploadToCloudinary(File(image.path));
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadToCloudinary(File image) async {
    if (_currentUser == null) return;
    try {
      setState(() => _isUploading = true);
      final cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);
      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(image.path, resourceType: CloudinaryResourceType.Image, folder: 'voyage/profiles', publicId: 'profile_${_currentUser!.uid}'),
      );
      final imageUrl = response.secureUrl;
      
      await _currentUser!.updatePhotoURL(imageUrl);
      await _firestore.collection('users').doc(_currentUser!.uid).set({
        'cloudinaryPhotoUrl': imageUrl,
        'photoURL': imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      await _currentUser!.reload();
      if (mounted) setState(() { _photoUrl = imageUrl; });
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!'), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _updateProfileInfo() async {
    if (_currentUser == null) return;
    try {
      final newName = _nameController.text.trim();
      final newBio = _bioController.text.trim();
      
      if (newName.isEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name cannot be empty'), backgroundColor: Colors.red));
         return;
      }

      await _firestore.collection('users').doc(_currentUser!.uid).set({
        'displayName': newName,
        'bio': newBio,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      await _currentUser!.updateDisplayName(newName);
      
      if (mounted) {
        setState(() {
          _displayName = newName;
          _bio = newBio;
        });
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated'), backgroundColor: Colors.green));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showEditProfileModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85, // Tall modal
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20, 
          left: 20, right: 20, top: 20
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Edit Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            const SizedBox(height: 20),
            
            // Name Field
            const Text("Display Name", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            
            // Bio Field
            const Text("Bio", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _bioController,
              maxLines: 4,
              maxLength: 150,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[50],
                hintText: "Write something about yourself...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _updateProfileInfo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- BUILDERS ---

  @override
  Widget build(BuildContext context) {
    // 1. Loading State
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Guest View (Professional Looking)
   if (_currentUser == null) {
      return GuestView(
        title: "Join Voyage",
        message: "Create your profile to start sharing your travel moments with the world.",
        onLoginPressed: () {
           Provider.of<HomeController>(context, listen: false).navigateToLogin(context);
        },
      );
    }

    // 3. User View
    return PopScope(
      canPop: false, 
      onPopInvoked: (didPop) async {
        if (didPop) return;
        Provider.of<AudioService>(context, listen: false).stop();
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
            onPressed: () {
               Provider.of<AudioService>(context, listen: false).stop();
               Navigator.pop(context);
            },
          ),
          centerTitle: true,
          title: const Text('My Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          actions: [
             IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              onPressed: () {
                 // Show confirmation
                 showDialog(
                   context: context, 
                   builder: (c) => AlertDialog(
                     title: const Text("Log Out"),
                     content: const Text("Are you sure you want to log out?"),
                     actions: [
                       TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
                       TextButton(
                         onPressed: () async {
                            Navigator.pop(c); // Close dialog
                            Provider.of<AudioService>(context, listen: false).stop();
                            await _auth.signOut();
                            if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
                         }, 
                         child: const Text("Log Out", style: TextStyle(color: Colors.red))
                       ),
                     ],
                   )
                 );
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        // Profile Avatar
                        GestureDetector(
                          onTap: _pickImage,
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey[300]!, width: 1),
                                ),
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Colors.grey[100],
                                  backgroundImage: _photoUrl.isNotEmpty ? CachedNetworkImageProvider(_photoUrl) : null,
                                  child: _photoUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                                ),
                              ),
                              Positioned(
                                bottom: 0, right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.edit, size: 12, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Name & Bio
                        Text(_displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        if (_bio.isNotEmpty)
                          Text(_bio, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700], fontSize: 14))
                        else 
                          const Text("No bio yet", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                          
                        const SizedBox(height: 24),
                        
                        // Action Buttons (Row)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _showEditProfileModal,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  side: BorderSide(color: Colors.grey[300]!),
                                ),
                                child: const Text("Edit Profile", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  // Navigate to the management list view we created earlier
                                  Provider.of<AudioService>(context, listen: false).stop();
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => const MyPostsPage()));
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  side: BorderSide(color: Colors.grey[300]!),
                                ),
                                child: const Text("Manage Posts", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
                
                // Sticky Header for "Posts"
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverAppBarDelegate(
                    child: Container(
                      color: Colors.white,
                      child: Column(
                        children: [
                          const Divider(height: 1),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.grid_on, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  "$_postsCount POSTS", 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                  ),
                ),

                // Posts Grid
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('posts')
                      .where('userId', isEqualTo: _currentUser?.uid)
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
                    }
                    
                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 60.0),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(color: Colors.grey[50], shape: BoxShape.circle),
                                child: Icon(Icons.camera_alt_outlined, size: 40, color: Colors.grey[400]),
                              ),
                              const SizedBox(height: 16),
                              Text("Capture your first memory", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      );
                    }

                    return SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 1,
                        mainAxisSpacing: 1,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          List<dynamic>? urls = data['imageUrls'] as List<dynamic>?;
                          String? imageUrl = (urls != null && urls.isNotEmpty) ? urls[0] : data['image'];
                          bool isMulti = (urls != null && urls.length > 1);

                          return GestureDetector(
                            onTap: () {
                               Provider.of<AudioService>(context, listen: false).stop();
                               Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => PostDetailPage(postId: docs[index].id)),
                              );
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(
                                  color: Colors.grey[200],
                                  child: imageUrl != null 
                                    ? CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 400, // Optimize memory
                                      )
                                    : const Icon(Icons.image),
                                ),
                                if (isMulti)
                                  const Positioned(
                                    top: 6, right: 6,
                                    child: Icon(Icons.filter_none, color: Colors.white, size: 16, shadows: [Shadow(color: Colors.black54, blurRadius: 2)]),
                                  ),
                              ],
                            ),
                          );
                        },
                        childCount: docs.length,
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
            
            // Uploading Indicator Overlay
            if (_isUploading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text("Uploading...", style: TextStyle(color: Colors.white))
                    ],
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  }

// Helper for the Sticky Header
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SliverAppBarDelegate({required this.child});

  @override
  double get minExtent => 50;
  @override
  double get maxExtent => 50;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}