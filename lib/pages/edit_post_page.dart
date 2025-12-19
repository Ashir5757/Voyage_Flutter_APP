import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tour/pages/music_selection_page.dart';

class EditPostPage extends StatefulWidget {
  final Map<String, dynamic> postData;
  final String postId;

  const EditPostPage({
    super.key, 
    required this.postData, 
    required this.postId
  });

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  // Controllers
  late TextEditingController _locationController;
  late TextEditingController _descriptionController;
  
  // Image State
  List<String> _existingImageUrls = []; // URLs from Firebase
  final List<XFile> _newImages = [];    // New files from Gallery
  bool _isUpdating = false;
  
  // Music State
  String? _selectedMusicUrl;
  String? _selectedMusicTitle;
  String? _selectedMusicArtist;
  
  // Audio Player
  final AudioPlayer _musicPlayer = AudioPlayer();
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  
  // Cloudinary Config (Same as AddPost)
  final String _cloudName = 'dseozz7gs'; 
  final String _uploadPreset = 'voyage_profile_upload'; 

  @override
  void initState() {
    super.initState();
    _initializeData();
    _setupAudioListeners();
  }

  void _initializeData() {
    // 1. Text Fields
    _locationController = TextEditingController(text: widget.postData['location']);
    _descriptionController = TextEditingController(text: widget.postData['description']);

    // 2. Images
    if (widget.postData['imageUrls'] != null) {
      _existingImageUrls = List<String>.from(widget.postData['imageUrls']);
    } else if (widget.postData['image'] != null) {
      _existingImageUrls = [widget.postData['image']];
    }

    // 3. Music
    _selectedMusicUrl = widget.postData['musicUrl'];
    _selectedMusicTitle = widget.postData['musicTitle'];
    _selectedMusicArtist = widget.postData['musicArtist'];

    // 4. Pre-load music if exists
    if (_selectedMusicUrl != null) {
      _loadMusic();
    }
  }

  Future<void> _loadMusic() async {
    try {
      await _musicPlayer.setUrl(_selectedMusicUrl!);
    } catch (e) {
      print("Error pre-loading music: $e");
    }
  }

  void _setupAudioListeners() {
    _musicPlayer.positionStream.listen((position) {
      if (mounted) setState(() => _currentPosition = position);
    });
    _musicPlayer.durationStream.listen((duration) {
      if (mounted && duration != null) setState(() => _totalDuration = duration);
    });
    _musicPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });
  }

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    _musicPlayer.dispose();
    super.dispose();
  }

  // --- IMAGE HANDLING ---

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty && mounted) {
      setState(() {
        _newImages.addAll(pickedFiles);
      });
    }
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
    });
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  Future<List<String>> _uploadNewImages() async {
    if (_newImages.isEmpty) return [];

    final List<String> newUrls = [];
    final cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);
    
    for (int i = 0; i < _newImages.length; i++) {
      try {
        final response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(
            _newImages[i].path,
            resourceType: CloudinaryResourceType.Image,
            folder: 'voyage/posts/${widget.postId}',
            // Use timestamp to avoid overwriting if user adds images multiple times
            publicId: '${widget.postId}_new_${DateTime.now().millisecondsSinceEpoch}_$i', 
          ),
        );
        newUrls.add(response.secureUrl);
      } catch (e) {
        print('Upload failed for image $i: $e');
        throw Exception('Failed to upload image');
      }
    }
    return newUrls;
  }

  // --- SAVE LOGIC ---

  Future<void> _updatePost() async {
    if (!mounted) return;

    // Validation
    if (_existingImageUrls.isEmpty && _newImages.isEmpty) {
      _showSnackbar('Post must have at least one image', Colors.red);
      return;
    }
    if (_locationController.text.isEmpty) {
      _showSnackbar('Location cannot be empty', Colors.red);
      return;
    }

    setState(() => _isUpdating = true);

    try {
      // 1. Upload NEW images (if any)
      List<String> uploadedNewUrls = [];
      if (_newImages.isNotEmpty) {
        uploadedNewUrls = await _uploadNewImages();
      }

      // 2. Combine Old + New URLs
      final List<String> finalImageUrls = [..._existingImageUrls, ...uploadedNewUrls];

      // 3. Update Firestore
      await FirebaseFirestore.instance.collection('posts').doc(widget.postId).update({
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'imageUrls': finalImageUrls,
        // Also update legacy single image field for compatibility
        'image': finalImageUrls.isNotEmpty ? finalImageUrls.first : null,
        
        // Music Updates
        'musicUrl': _selectedMusicUrl,
        'musicTitle': _selectedMusicTitle,
        'musicArtist': _selectedMusicArtist,
      });

      if (mounted) {
        _showSnackbar('Post updated successfully!', Colors.green);
        Navigator.pop(context); // Go back
      }

    } catch (e) {
      print('Update Error: $e');
      if (mounted) _showSnackbar('Failed to update post', Colors.red);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  // --- MUSIC NAVIGATION ---
  Future<void> _navigateToMusicSelection() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MusicSelectionPage()),
    );
    
    if (result != null && mounted) {
      setState(() {
        _selectedMusicUrl = result['musicUrl'];
        _selectedMusicTitle = result['musicTitle'];
        _selectedMusicArtist = result['musicArtist'];
      });
      
      try {
        await _musicPlayer.stop();
        await _musicPlayer.setUrl(_selectedMusicUrl!);
        await _musicPlayer.play();
      } catch (e) {
        print("Error playing new music: $e");
      }
    }
  }

  // --- WIDGET BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Edit Post', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: _isUpdating ? null : _updatePost,
              child: _isUpdating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('SAVE', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
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
              _buildImageSection(),
              const SizedBox(height: 24),
              _buildInputSection(
                icon: Icons.location_on_outlined,
                title: 'Location',
                hint: 'Where was this?',
                controller: _locationController,
              ),
              const SizedBox(height: 20),
              _buildInputSection(
                icon: Icons.description_outlined,
                title: 'Description',
                hint: 'Update your story...',
                controller: _descriptionController,
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              _buildMusicSection(),
              if (_selectedMusicUrl != null) _buildMiniPlayer(),
              const SizedBox(height: 30),
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
            Text('Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
            const SizedBox(width: 8),
            Text('(${_existingImageUrls.length + _newImages.length} total)', style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 8),
        
        // Add Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_photo_alternate, size: 18),
            label: const Text('Add More Photos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[50],
              foregroundColor: Colors.blue[800],
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Horizontal Scroll of Images
        if (_existingImageUrls.isNotEmpty || _newImages.isNotEmpty)
          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // 1. Existing Images (Network)
                ..._existingImageUrls.asMap().entries.map((entry) {
                  return _buildImagePreview(
                    isNetwork: true,
                    pathOrUrl: entry.value,
                    onDelete: () => _removeExistingImage(entry.key),
                  );
                }),
                // 2. New Images (File)
                ..._newImages.asMap().entries.map((entry) {
                  return _buildImagePreview(
                    isNetwork: false,
                    pathOrUrl: entry.value.path,
                    onDelete: () => _removeNewImage(entry.key),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildImagePreview({
    required bool isNetwork,
    required String pathOrUrl,
    required VoidCallback onDelete,
  }) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: isNetwork
                ? CachedNetworkImage(
                    imageUrl: pathOrUrl,
                    width: 120, height: 150, fit: BoxFit.cover,
                    placeholder: (c, u) => Container(color: Colors.grey[200]),
                  )
                : Image.file(
                    File(pathOrUrl),
                    width: 120, height: 150, fit: BoxFit.cover,
                  ),
          ),
          // Delete Badge
          Positioned(
            top: 6, right: 6,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
          // "New" Badge
          if (!isNetwork)
             Positioned(
              bottom: 6, right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(4)),
                child: const Text("NEW", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
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
            Text('Travel Music', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
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
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _selectedMusicArtist ?? 'Unknown Artist',
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        )
                      : const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Change Music', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('Tap to browse Jamendo', style: TextStyle(fontSize: 14, color: Colors.grey)),
                          ],
                        ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
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
              child: const Text('Remove Music', style: TextStyle(color: Colors.red)),
            ),
          ),
      ],
    );
  }

  Widget _buildMiniPlayer() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: () async {
                  if (_isPlaying) await _musicPlayer.pause();
                  else await _musicPlayer.play();
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selectedMusicTitle ?? 'No Title', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1),
                    Text(_selectedMusicArtist ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}