import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'dart:io';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  _UserProfilePageState createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  File? _profileImage;
  User? _currentUser;
  String _originalName = '';
  String _originalEmail = '';
  String _originalPhotoUrl = '';
  String _originalBio = '';
  bool _isLoading = true;
  bool _isUploading = false;
  
  // Cloudinary Configuration
  // Get these from your Cloudinary dashboard
   final String _cloudName = 'dseozz7gs'; // Get from Cloudinary dashboard

  final String _uploadPreset = 'voyage_profile_upload';// Create this in Cloudinary

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
      _originalName = user.displayName ?? 'Traveler';
      _originalEmail = user.email ?? 'user@example.com';
      _originalPhotoUrl = user.photoURL ?? '';
      
      // Load custom data from Firestore
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        _nameController.text = data['displayName'] as String? ?? _originalName;
        _bioController.text = data['bio'] as String? ?? 'Travel enthusiast';
        _originalBio = _bioController.text;
        
        // Use Cloudinary URL if available, otherwise Firebase URL
        final cloudinaryUrl = data['cloudinaryPhotoUrl'] as String?;
        if (cloudinaryUrl != null && cloudinaryUrl.isNotEmpty) {
          _originalPhotoUrl = cloudinaryUrl;
        }
      } else {
        _nameController.text = _originalName;
        _bioController.text = 'Travel enthusiast';
        _originalBio = 'Travel enthusiast';
      }
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.deepPurple),
              title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () async {
                Navigator.pop(context);
                final image = await _picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1000,
                  imageQuality: 85,
                );
                if (image != null) {
                  await _uploadToCloudinary(File(image.path));
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.deepPurple),
              title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () async {
                Navigator.pop(context);
                final image = await _picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1000,
                  imageQuality: 85,
                );
                if (image != null) {
                  await _uploadToCloudinary(File(image.path));
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadToCloudinary(File image) async {
    if (_currentUser == null) return;
    
    try {
      setState(() => _isUploading = true);
      
      // Initialize Cloudinary with your cloud name and upload preset
      final cloudinary = CloudinaryPublic(
        _cloudName,          // Your cloud name
        _uploadPreset,       // Your upload preset name
        cache: false,
      );
      
      // Upload the image
      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          image.path,
          resourceType: CloudinaryResourceType.Image,
          folder: 'voyage/profiles',
          publicId: 'profile_${_currentUser!.uid}_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );

      final imageUrl = response.secureUrl;
      
      print('Image uploaded to Cloudinary: $imageUrl');
      
      // Update in Firebase Auth
      await _currentUser!.updatePhotoURL(imageUrl);
      
      // Update in Firestore with Cloudinary URL
      await _firestore.collection('users').doc(_currentUser!.uid).set({
        'cloudinaryPhotoUrl': imageUrl,
        'photoURL': imageUrl, // Keep for backward compatibility
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      // Reload user data
      await _currentUser!.reload();
      _currentUser = _auth.currentUser;
      
      setState(() {
        _originalPhotoUrl = imageUrl;
        _profileImage = null; // Clear local file
      });
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile picture updated!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      print('Cloudinary upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _updateProfile() async {
    if (_currentUser == null) return;
    
    final newName = _nameController.text.trim();
    final newBio = _bioController.text.trim();
    
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a display name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      setState(() => _isUploading = true);
      
      // Update in Firestore
      final updates = {
        'displayName': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      if (newBio.isNotEmpty) {
        updates['bio'] = newBio;
      }
      
      await _firestore.collection('users').doc(_currentUser!.uid).set(
        updates,
        SetOptions(merge: true),
      );
      
      // Update display name in Firebase Auth
      await _currentUser!.updateDisplayName(newName);
      
      setState(() {
        _originalName = newName;
        _originalBio = newBio;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.deepPurple,
                strokeWidth: 2,
              ),
            )
          : _currentUser == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Please login to view profile',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushReplacementNamed(context, '/login');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 14,
                          ),
                        ),
                        child: const Text(
                          'Go to Login',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    CustomScrollView(
                      slivers: [
                        // App Bar
                        SliverAppBar(
                          expandedHeight: 200,
                          floating: false,
                          pinned: true,
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          flexibleSpace: FlexibleSpaceBar(
                            title: Text(
                              'My Profile',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            background: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.deepPurple.shade800,
                                    Colors.purple.shade600,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Profile Content
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                // Profile Picture Section
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 150,
                                      height: 150,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.deepPurple.shade400,
                                            Colors.purpleAccent.shade400,
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.deepPurple.withOpacity(0.3),
                                            blurRadius: 15,
                                            spreadRadius: 3,
                                          ),
                                        ],
                                      ),
                                      child: ClipOval(
                                        child: _originalPhotoUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: _originalPhotoUrl,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) =>
                                                    Container(
                                                      color: Colors.white.withOpacity(0.2),
                                                      child: const Center(
                                                        child: CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2,
                                                        ),
                                                      ),
                                                    ),
                                                errorWidget: (context, url, error) =>
                                                    Container(
                                                      color: Colors.white.withOpacity(0.2),
                                                      child: const Icon(
                                                        Icons.person,
                                                        size: 60,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                              )
                                            : Container(
                                                color: Colors.white.withOpacity(0.2),
                                                child: const Icon(
                                                  Icons.person,
                                                  size: 60,
                                                  color: Colors.white,
                                                ),
                                              ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 5,
                                      right: 5,
                                      child: GestureDetector(
                                        onTap: _pickImage,
                                        child: Container(
                                          width: 45,
                                          height: 45,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.2),
                                                blurRadius: 8,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.camera_alt,
                                            color: Colors.deepPurple,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // User Info
                                Text(
                                  _originalName,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _originalEmail,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 30),

                                // Email Verification Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _currentUser!.emailVerified
                                        ? Colors.green.shade50
                                        : Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(25),
                                    border: Border.all(
                                      color: _currentUser!.emailVerified
                                          ? Colors.green.shade200
                                          : Colors.orange.shade200,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _currentUser!.emailVerified
                                            ? Icons.verified
                                            : Icons.warning_amber_rounded,
                                        color: _currentUser!.emailVerified
                                            ? Colors.green.shade600
                                            : Colors.orange.shade600,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _currentUser!.emailVerified
                                            ? 'Email Verified'
                                            : 'Email Not Verified',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: _currentUser!.emailVerified
                                              ? Colors.green.shade800
                                              : Colors.orange.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 30),

                                // Edit Profile Card
                                Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      children: [
                                        const Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Edit Profile',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.deepPurple,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),

                                        // Name Field
                                        TextField(
                                          controller: _nameController,
                                          decoration: InputDecoration(
                                            labelText: 'Display Name',
                                            hintText: 'Enter your name',
                                            prefixIcon: const Icon(
                                              Icons.person_outline,
                                              color: Colors.deepPurple,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide.none,
                                            ),
                                            filled: true,
                                            fillColor: Colors.grey[50],
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 16,
                                            ),
                                          ),
                                          style: const TextStyle(
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 20),

                                        
                                        const SizedBox(height: 25),

                                        // Update Button
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: _updateProfile,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.deepPurple,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 16,
                                              ),
                                              elevation: 3,
                                              shadowColor: Colors.deepPurple.withOpacity(0.3),
                                            ),
                                            child: const Text(
                                              'Save Changes',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 25),

                                // Account Actions
                                Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    children: [
                                      ListTile(
                                        leading: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.logout,
                                            color: Colors.red,
                                          ),
                                        ),
                                        title: const Text(
                                          'Sign Out',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.red,
                                          ),
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                          color: Colors.red,
                                        ),
                                        onTap: () async {
                                          await _auth.signOut();
                                          if (mounted) {
                                            Navigator.pushReplacementNamed(context, '/');
                                          }
                                        },
                                      ),
                                      Divider(
                                        height: 1,
                                        color: Colors.grey[200],
                                        indent: 16,
                                        endIndent: 16,
                                      ),
                                      ListTile(
                                        leading: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                        ),
                                        title: const Text(
                                          'Delete Account',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.red,
                                          ),
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                          color: Colors.red,
                                        ),
                                        onTap: () {
                                          _showDeleteConfirmation();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 30),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Uploading Overlay
                    if (_isUploading)
                      Container(
                        color: Colors.black.withOpacity(0.7),
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                              SizedBox(height: 20),
                              Text(
                                'Updating...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'This action cannot be undone. All your data will be permanently deleted.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    // Implement account deletion logic here
    // Note: This requires additional Firebase setup
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account deletion feature coming soon'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}