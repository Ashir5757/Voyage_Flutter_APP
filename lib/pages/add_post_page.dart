// lib/pages/add_post_page.dart - UPDATED WITH CLOUDINARY
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:intl/intl.dart';
import 'package:tour/pages/music_selection_page.dart';
import 'package:uuid/uuid.dart';

class AddPostPage extends StatefulWidget {
  const AddPostPage({super.key});

  @override
  State<AddPostPage> createState() => _AddPostPageState();
}

class _AddPostPageState extends State<AddPostPage> {
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  final List<XFile> _selectedImages = [];
  bool _isUploading = false;
  
  String? _selectedMusicUrl;
  String? _selectedMusicTitle;
  String? _selectedMusicArtist;
  
  // Audio player for Spotify-style player
  final AudioPlayer _musicPlayer = AudioPlayer();
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();
  
  // Cloudinary Configuration
    final String _cloudName = 'dseozz7gs'; // Get from Cloudinary dashboard

  final String _uploadPreset = 'voyage_profile_upload'; // Create this preset in Cloudinary

  @override
  void initState() {
    super.initState();
    
    // Listen to player state changes
    _musicPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() => _currentPosition = position);
      }
    });

    _musicPlayer.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() => _totalDuration = duration);
      }
    });

    _musicPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state.playing);
      }
    });
  }

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    _musicPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty && mounted) {
      setState(() {
        _selectedImages.addAll(pickedFiles);
      });
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null && mounted) {
      setState(() => _selectedImages.add(pickedFile));
    }
  }

  void _removeImage(int index) {
    if (mounted) setState(() => _selectedImages.removeAt(index));
  }

  // Upload images to Cloudinary
  Future<List<String>> _uploadImagesToCloudinary(String postId) async {
    final List<String> imageUrls = [];
    
    // Initialize Cloudinary
    final cloudinary = CloudinaryPublic(
      _cloudName,
      _uploadPreset,
      cache: false,
    );
    
    for (int i = 0; i < _selectedImages.length; i++) {
      try {
        final imageFile = File(_selectedImages[i].path);
        
        // Upload to Cloudinary
      final response = await cloudinary.uploadFile(
  CloudinaryFile.fromFile(
    imageFile.path,
    resourceType: CloudinaryResourceType.Image,
    folder: 'voyage/posts/$postId',
    publicId: '${postId}_$i',
  ),
);


        final imageUrl = response.secureUrl;
        final transformedUrl =
  response.secureUrl.replaceFirst(
    '/upload/',
    '/upload/w_1200,h_800,c_fill,q_auto:good/',
  );
        imageUrls.add(imageUrl);
        print('Uploaded image $i to Cloudinary: $imageUrl');
        
      } catch (e) {
        print('Cloudinary upload failed for image $i: $e');
        throw Exception('Failed to upload image ${i + 1}: $e');
      }
    }
    
    return imageUrls;
  }

// Helper method to apply transformations to Cloudinary URL
String _applyTransformationToUrl(String originalUrl) {
  // Cloudinary URL format: https://res.cloudinary.com/cloudname/image/upload/v1234567/folder/image.jpg
  // We insert transformation parameters after '/upload/'
  
  // Check if URL is already a Cloudinary URL
  if (originalUrl.contains('res.cloudinary.com')) {
    // Insert transformation parameters
    final transformedUrl = originalUrl.replaceFirst(
      '/upload/',
      '/upload/w_1200,h_800,c_fill,q_auto:good/', // Your desired transformation
    );
    return transformedUrl;
  }
  
  // If not a Cloudinary URL (shouldn't happen), return original
  return originalUrl;
}

  Future<void> _uploadPost() async {
    // Check if still mounted before starting
    if (!mounted) return;
    
    // Validation
    if (_selectedImages.isEmpty) {
      if (mounted) _showSnackbar('Please select at least one image', Colors.red);
      return;
    }
    if (_locationController.text.isEmpty) {
      if (mounted) _showSnackbar('Please enter a location', Colors.red);
      return;
    }
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      if (mounted) _showSnackbar('You must be logged in to post', Colors.red);
      return;
    }

    if (mounted) setState(() => _isUploading = true);

    try {
      print('=== Starting upload with Cloudinary ===');
      
      // Generate post data
      final postId = _uuid.v4();
      final timestamp = DateTime.now();
      final formattedDate = DateFormat('yyyy-MM-dd – HH:mm').format(timestamp);
      
      // Get user info
      DocumentSnapshot userDoc;
      try {
        userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      } catch (e) {
        print(' Error getting user doc: $e');
        if (mounted) _showSnackbar('Error fetching user data', Colors.red);
        return;
      }
      
      String userName;
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>?;
        userName = userData?['name'] ?? currentUser.displayName ?? 'Anonymous';
      } else {
        userName = currentUser.displayName ?? 'Anonymous';
      }

      // Upload images to Cloudinary
      final List<String> imageUrls;
      try {
        imageUrls = await _uploadImagesToCloudinary(postId);
        print('All images uploaded successfully to Cloudinary');
      } catch (e) {
        print('Cloudinary upload error: $e');
        if (mounted) {
          _showSnackbar('Failed to upload images: $e', Colors.red);
          setState(() => _isUploading = false);
        }
        return;
      }

      // Create post data
      final postData = {
        'postId': postId,
        'userId': currentUser.uid,
        'userName': userName,
        'userEmail': currentUser.email ?? '',
        'userPhoto': currentUser.photoURL ?? '',
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'imageUrls': imageUrls,
        'musicUrl': _selectedMusicUrl,
        'musicTitle': _selectedMusicTitle,
        'musicArtist': _selectedMusicArtist,
        'likes': 0,
        'comments': 0,
        'createdAt': timestamp,
        'formattedDate': formattedDate,
        'isActive': true,
        'likedBy': [],
        'viewCount': 0,
        'cloudinaryUpload': true, // Mark that this was uploaded to Cloudinary
      };

      try {
        // Save to Firestore
        await _firestore.collection('posts').doc(postId).set(postData);
        
        // Update user count
        await _firestore.collection('users').doc(currentUser.uid).set({
          'postsCount': FieldValue.increment(1),
          'lastPostDate': timestamp,
        }, SetOptions(merge: true));

        print('=== Post upload successful ===');
        
        if (mounted) {
          _showSnackbar('Post shared successfully!', Colors.green);
          _clearForm();
          Navigator.pop(context);
        }

      } on FirebaseException catch (e) {
        print('Firestore error: ${e.code} - ${e.message}');
        
        if (mounted) {
          if (e.code == 'unknown' && e.message?.contains('terminated') == true) {
            _showSnackbar('Connection lost. Please try again.', Colors.red);
          } else if (e.code == 'unavailable') {
            _showSnackbar('Network issue. Please check connection.', Colors.red);
          } else {
            _showSnackbar('Upload failed: ${e.code}', Colors.red);
          }
        }
      }

    } catch (e) {
      print(' Upload error: $e');
      if (mounted) _showSnackbar('Upload failed. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _clearForm() {
    if (mounted) {
      setState(() {
        _selectedImages.clear();
        _locationController.clear();
        _descriptionController.clear();
        _selectedMusicUrl = null;
        _selectedMusicTitle = null;
        _selectedMusicArtist = null;
        _isUploading = false;
      });
      _musicPlayer.stop();
    }
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Navigate to music selection page
  Future<void> _navigateToMusicSelection() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MusicSelectionPage(),
      ),
    );
    
    if (result != null && mounted) {
      setState(() {
        _selectedMusicUrl = result['musicUrl'];
        _selectedMusicTitle = result['musicTitle'];
        _selectedMusicArtist = result['musicArtist'];
      });
      
      // Load and play the selected music
      try {
        await _musicPlayer.stop();
        await _musicPlayer.setUrl(_selectedMusicUrl!);
        await _musicPlayer.play();
      } catch (e) {
        print('Error loading music: $e');
        if (mounted) {
          _showSnackbar('Could not play music preview', Colors.orange);
        }
      }
    }
  }

  // Spotify-style mini player widget
  Widget _buildMiniPlayer() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () async {
                  if (_isPlaying) {
                    await _musicPlayer.pause();
                  } else {
                    await _musicPlayer.play();
                  }
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedMusicTitle ?? 'No Title',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _selectedMusicArtist ?? 'Unknown Artist',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.stop,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () async {
                  await _musicPlayer.stop();
                  setState(() {
                    _currentPosition = Duration.zero;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Progress bar
          StreamBuilder<Duration>(
            stream: _musicPlayer.positionStream,
            builder: (context, positionSnapshot) {
              final position = positionSnapshot.data ?? Duration.zero;
              
              return StreamBuilder<Duration?>(
                stream: _musicPlayer.durationStream,
                builder: (context, durationSnapshot) {
                  final duration = durationSnapshot.data ?? Duration.zero;
                  final maxMs = duration.inMilliseconds.toDouble();
                  final currentMs = position.inMilliseconds.toDouble();
                  
                  return Column(
                    children: [
                      Slider(
                        min: 0,
                        max: maxMs > 0 ? maxMs : 1,
                        value: currentMs.clamp(0, maxMs),
                        onChanged: (value) async {
                          await _musicPlayer.seek(Duration(milliseconds: value.toInt()));
                        },
                        activeColor: Colors.greenAccent,
                        inactiveColor: Colors.white24,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Create Post', 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: _isUploading ? null : _uploadPost,
              child: _isUploading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('POST', 
                      style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Info
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: currentUser?.photoURL != null
                        ? NetworkImage(currentUser!.photoURL!)
                        : const AssetImage('images/boy.jpg') as ImageProvider,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentUser?.displayName ?? 'Traveler',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentUser?.email ?? 'User',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Images Section
              _buildImageSection(),
              
              const SizedBox(height: 24),
              
              // Location
              _buildInputSection(
                icon: Icons.location_on_outlined,
                title: 'Location',
                hint: 'Where did you travel? (e.g., Paris, France)',
                controller: _locationController,
              ),
              
              const SizedBox(height: 20),
              
              // Description
              _buildInputSection(
                icon: Icons.description_outlined,
                title: 'Description',
                hint: 'Share your travel experience...',
                controller: _descriptionController,
                maxLines: 4,
              ),
              
              const SizedBox(height: 20),
              
              // Music Selection Section
              _buildMusicSection(),
              
              // Spotify-style mini player
              if (_selectedMusicUrl != null) _buildMiniPlayer(),
              
              const SizedBox(height: 30),
              
              // Upload Button with Cloudinary info
              Column(
                children: [
                  if (!_isUploading)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            'Uploading via Cloudinary',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _uploadPost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isUploading ? Colors.grey : Colors.blue[800],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isUploading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                SizedBox(width: 12),
                                Text('Uploading to Cloudinary...'),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_upload_outlined),
                                SizedBox(width: 10),
                                Text('Share Your Travel Story'),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library, color: Colors.blue),
            const SizedBox(width: 8),
            Text('Travel Photos', 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
            const SizedBox(width: 8),
            Text('(${_selectedImages.length} selected)',
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 8),
        
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Add from Gallery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[50],
                  foregroundColor: Colors.blue[800],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Take Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[50],
                  foregroundColor: Colors.green[800],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        if (_selectedImages.isNotEmpty) ...[
          const Text('Tap X to remove',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) => _buildImagePreview(index),
            ),
          ),
        ] else ...[
          Container(
            width: double.infinity,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_library, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                const Text('Add your travel photos',
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
                const Text('Select multiple images',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImagePreview(int index) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_selectedImages[index].path),
              width: 120,
              height: 150,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 8, right: 8,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection({
    required IconData icon,
    required String title,
    required String hint,
    required TextEditingController controller,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 8),
            Text(title, 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMusicSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.music_note, color: Colors.purple),
            const SizedBox(width: 8),
            Text('Travel Music', 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
          ],
        ),
        const SizedBox(height: 8),
        
        GestureDetector(
          onTap: _navigateToMusicSelection,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedMusicUrl != null ? Colors.purple : Colors.grey[300]!,
                width: _selectedMusicUrl != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.music_note,
                  color: _selectedMusicUrl != null ? Colors.purple : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _selectedMusicUrl != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedMusicTitle ?? 'Unknown Title',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_selectedMusicArtist != null)
                              Text(
                                _selectedMusicArtist!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        )
                      : const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add Music to Your Post',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Tap to browse free music from Jamendo',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: _selectedMusicUrl != null ? Colors.purple : Colors.grey,
                ),
              ],
            ),
          ),
        ),
        
        if (_selectedMusicUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () {
                setState(() {
                  _selectedMusicUrl = null;
                  _selectedMusicTitle = null;
                  _selectedMusicArtist = null;
                });
                _musicPlayer.stop();
              },
              child: const Text(
                'Remove Music',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),
      ],
    );
  }
}