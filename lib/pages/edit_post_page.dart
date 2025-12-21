import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Added for User Profile
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tour/pages/music_selection_page.dart';
import 'package:tour/services/storage_service.dart'; // Secure Service

class EditPostPage extends StatefulWidget {
  final Map<String, dynamic> currentData; 
  final String postId;

  const EditPostPage({
    super.key, 
    required this.currentData, 
    required this.postId
  });

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  // --- SECURE STORAGE SERVICE ---
  final StorageService _storage = CloudinaryStorageService();

  late TextEditingController _locationController;
  late TextEditingController _descriptionController;
  
  // Image State
  List<String> _existingImageUrls = []; 
  final List<XFile> _newImages = [];    
  final List<String> _imagesToDeleteFromCloud = []; // Smart Delete Queue

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
  
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _setupAudioListeners();
  }

  void _initializeData() {
    _locationController = TextEditingController(text: widget.currentData['location']);
    _descriptionController = TextEditingController(text: widget.currentData['description']);

    if (widget.currentData['imageUrls'] != null) {
      _existingImageUrls = List<String>.from(widget.currentData['imageUrls']);
    } else if (widget.currentData['image'] != null) {
      _existingImageUrls = [widget.currentData['image']];
    }

    _selectedMusicUrl = widget.currentData['musicUrl'];
    _selectedMusicTitle = widget.currentData['musicTitle'];
    _selectedMusicArtist = widget.currentData['musicArtist'];

    if (_selectedMusicUrl != null) {
      _loadMusic();
    }
  }

  Future<void> _loadMusic() async {
    try {
      await _musicPlayer.setUrl(_selectedMusicUrl!);
    } catch (e) {
      debugPrint("Error pre-loading music: $e");
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

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null && mounted) {
      setState(() => _newImages.add(pickedFile));
    }
  }

  void _removeExistingImage(int index) {
    setState(() {
      _imagesToDeleteFromCloud.add(_existingImageUrls[index]); // Mark for deletion
      _existingImageUrls.removeAt(index);
    });
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  // --- SAVE LOGIC ---

  Future<void> _updatePost() async {
    if (!mounted) return;

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
      // 1. Upload NEW images via Service
      List<String> uploadedNewUrls = [];
      if (_newImages.isNotEmpty) {
        uploadedNewUrls = await _storage.uploadImages(_newImages, widget.postId);
      }

      // 2. Combine URLs (Set avoids duplicates)
      final List<String> finalImageUrls = {..._existingImageUrls, ...uploadedNewUrls}.toList();

      // 3. Update Firestore
      await FirebaseFirestore.instance.collection('posts').doc(widget.postId).update({
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'imageUrls': finalImageUrls,
        'image': finalImageUrls.isNotEmpty ? finalImageUrls.first : null,
        'musicUrl': _selectedMusicUrl,
        'musicTitle': _selectedMusicTitle,
        'musicArtist': _selectedMusicArtist,
      });

      // 4. Clean up Cloudinary (Delete removed images)
      for (String url in _imagesToDeleteFromCloud) {
        await _storage.deleteImage(url);
      }

      if (mounted) {
        _showSnackbar('Post updated successfully!', Colors.green);
        Navigator.pop(context);
      }

    } catch (e) {
      debugPrint('Update Error: $e');
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

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

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
        if (mounted) _showSnackbar('Could not play music preview', Colors.orange);
      }
    }
  }

  // --- UI BUILD ---

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
        title: const Text('Edit Post', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
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
              // --- 1. USER PROFILE ROW (Copied from AddPost) ---
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

              // --- 2. BOTTOM BIG BUTTON (Copied from AddPost) ---
              Column(
                children: [
                  if (!_isUpdating)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            'Updating via Cloudinary',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isUpdating ? null : _updatePost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isUpdating ? Colors.grey : Colors.blue[800],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isUpdating
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                SizedBox(width: 12),
                                Text('Updating Voyage...'),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.edit_note),
                                SizedBox(width: 10),
                                Text('Update Voyage'),
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
            Text('Travel Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
            const SizedBox(width: 8),
            Text('(${_existingImageUrls.length + _newImages.length} total)', style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 8),
        
        // Dual Buttons (Gallery & Camera) - Matched AddPost
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Gallery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[50], 
                  foregroundColor: Colors.blue[800], 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), 
                  padding: const EdgeInsets.symmetric(vertical: 12)
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[50], 
                  foregroundColor: Colors.green[800], 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), 
                  padding: const EdgeInsets.symmetric(vertical: 12)
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        // Image List
        if (_existingImageUrls.isNotEmpty || _newImages.isNotEmpty)
          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Existing (Network)
                ..._existingImageUrls.asMap().entries.map((entry) {
                  return _buildImagePreview(
                    isNetwork: true,
                    pathOrUrl: entry.value,
                    onDelete: () => _removeExistingImage(entry.key),
                  );
                }),
                // New (File)
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
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 28),
                onPressed: () async {
                  if (_isPlaying) await _musicPlayer.pause();
                  else await _musicPlayer.play();
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selectedMusicTitle ?? 'No Title', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(_selectedMusicArtist ?? 'Unknown Artist', style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.stop, color: Colors.white, size: 24),
                onPressed: () async {
                  await _musicPlayer.stop();
                  setState(() => _currentPosition = Duration.zero);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                        onChanged: (value) async => await _musicPlayer.seek(Duration(milliseconds: value.toInt())),
                        activeColor: Colors.greenAccent,
                        inactiveColor: Colors.white24,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                            Text(_formatDuration(duration), style: const TextStyle(color: Colors.white70, fontSize: 10)),
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
}