import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

// IMPORTS
import 'package:tour/pages/music_selection_page.dart';
import 'package:tour/services/storage_service.dart';
import 'package:tour/widgets/editable_media_section.dart'; // Ensure this matches your file name

class EditPostPage extends StatefulWidget {
  final Map<String, dynamic> currentData; 
  final String postId;

  const EditPostPage({super.key, required this.currentData, required this.postId});

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  final StorageService _storage = CloudinaryStorageService();

  late TextEditingController _locationController;
  late TextEditingController _descriptionController;
  
  // 1. SNAPSHOT: The "Before" state (used for deletion logic)
  List<String> _originalUrls = [];
  
  // 2. WORKING LISTS: The "After" state
  List<String> _existingImageUrls = []; // URLs already on cloud
  List<XFile> _newImages = [];          // New files from phone (NEED UPLOAD)

  bool _isUpdating = false;
  
  // Music vars
  String? _selectedMusicUrl;
  String? _selectedMusicTitle;
  String? _selectedMusicArtist;
  
  final AudioPlayer _musicPlayer = AudioPlayer();
  bool _isPlaying = false;
  
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _locationController = TextEditingController(text: widget.currentData['location']);
    _descriptionController = TextEditingController(text: widget.currentData['description']);

    // Initialize the working list from passed data
    if (widget.currentData['imageUrls'] != null) {
      _existingImageUrls = List<String>.from(widget.currentData['imageUrls']);
    } else if (widget.currentData['image'] != null) {
      _existingImageUrls = [widget.currentData['image']];
    }
    
    // Save original state for comparison later
    _originalUrls = List.from(_existingImageUrls);

    _selectedMusicUrl = widget.currentData['musicUrl'];
    _selectedMusicTitle = widget.currentData['musicTitle'];
    _selectedMusicArtist = widget.currentData['musicArtist'];

    if (_selectedMusicUrl != null) _loadMusic();
    _setupAudioListeners();
  }

  Future<void> _loadMusic() async {
    try { await _musicPlayer.setUrl(_selectedMusicUrl!); } catch (e) { debugPrint("$e"); }
  }

  void _setupAudioListeners() {
    _musicPlayer.playerStateStream.listen((s) {
      if (mounted) setState(() => _isPlaying = s.playing);
    });
  }

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    _musicPlayer.dispose();
    super.dispose();
  }

  // --- ACTIONS ---

  void _removeExistingImage(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
    });
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
  }

  // ---------------------------------------------------------
  // ⚡ THE FIX IS HERE: UPLOAD NEW + MERGE WITH OLD
  // ---------------------------------------------------------
  Future<void> _updatePost() async {
    if (!mounted) return;
    
    // 1. Validation: Ensure we don't end up with 0 images
    if (_existingImageUrls.isEmpty && _newImages.isEmpty) {
      _showSnackbar('Post must have at least one photo or video', Colors.red);
      return;
    }
    
    setState(() => _isUpdating = true);

    try {
      // 2. UPLOAD NEW FILES (The missing step!)
      List<String> newUploadedUrls = [];
      if (_newImages.isNotEmpty) {
        // We use the same service as AddPostPage to upload the XFiles
        newUploadedUrls = await _storage.uploadImages(_newImages, widget.postId);
      }

      // 3. MERGE: Combine [Old URLs] + [New URLs]
      final List<String> finalImageUrls = [..._existingImageUrls, ...newUploadedUrls];

      // 4. CALCULATE DELETIONS (Diffing)
      // Any URL that was in _originalUrls but NOT in finalImageUrls must be deleted
      final List<String> urlsToDelete = _originalUrls
          .where((url) => !finalImageUrls.contains(url))
          .toList();

      print("--- UPDATE SUMMARY ---");
      print("Existing kept: ${_existingImageUrls.length}");
      print("New uploaded: ${newUploadedUrls.length}");
      print("Total Final: ${finalImageUrls.length}");
      print("Deleting: ${urlsToDelete.length}");

      // 5. UPDATE FIRESTORE & CLEANUP
      await Future.wait([
        // Update DB with the FINAL list
        FirebaseFirestore.instance.collection('posts').doc(widget.postId).update({
          'location': _locationController.text.trim(),
          'description': _descriptionController.text.trim(),
          'imageUrls': finalImageUrls, // <--- This now contains both!
          'image': finalImageUrls.isNotEmpty ? finalImageUrls.first : null,
          'musicUrl': _selectedMusicUrl,
          'musicTitle': _selectedMusicTitle,
          'musicArtist': _selectedMusicArtist,
        }),

        // Delete removed items
        _performCleanup(urlsToDelete),
      ]);

      if (mounted) {
        _showSnackbar('Voyage updated successfully!', Colors.green);
        Navigator.pop(context, true); // Return true to trigger refresh
      }
    } catch (e) {
      print("Update Error: $e");
      if (mounted) _showSnackbar('Failed to update. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _performCleanup(List<String> urls) async {
    for (String url in urls) {
      try {
        await _storage.deleteImage(url);
        await CachedNetworkImageProvider(url).evict();
        if (url.contains('/video/')) {
           final thumbUrl = url.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.jpg');
           await CachedNetworkImageProvider(thumbUrl).evict();
        }
      } catch (e) {
        print("Cleanup warning: $e");
      }
    }
  }

  void _showSnackbar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ---------------------------------------------------------
  // UI
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Edit Post', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        actions: [
          TextButton(
            onPressed: _isUpdating ? null : _updatePost,
            child: _isUpdating ? const CircularProgressIndicator() : const Text('SAVE'),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (currentUser != null) 
                 ListTile(
                   contentPadding: EdgeInsets.zero,
                   leading: CircleAvatar(backgroundImage: NetworkImage(currentUser.photoURL ?? 'https://via.placeholder.com/150')),
                   title: Text(currentUser.displayName ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold)),
                   subtitle: Text(currentUser.email ?? ''),
                 ),
              
              const SizedBox(height: 20),

              // --- REUSABLE EDITABLE SECTION ---
              EditableMediaSection(
                existingUrls: _existingImageUrls,
                newFiles: _newImages,
                // When user picks NEW files, update _newImages
                onNewFilesChanged: (List<XFile> updatedFiles) {
                  setState(() => _newImages = updatedFiles);
                },
                // When user removes EXISTING, call helper
                onRemoveExisting: _removeExistingImage,
                // When user removes NEW, call helper
                onRemoveNew: _removeNewImage,
              ),
              // --------------------------------

              const SizedBox(height: 20),
              _buildInputSection(Icons.location_on_outlined, 'Location', _locationController),
              const SizedBox(height: 20),
              _buildInputSection(Icons.description_outlined, 'Description', _descriptionController, maxLines: 4),
              const SizedBox(height: 20),
              _buildMusicSection(),
              if (_selectedMusicUrl != null) _buildMiniPlayer(),
              const SizedBox(height: 30),
              
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isUpdating ? null : _updatePost,
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(_isUpdating ? 'Updating...' : 'Update Voyage'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputSection(IconData icon, String hint, TextEditingController controller, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
      child: TextField(
        controller: controller, maxLines: maxLines,
        decoration: InputDecoration(prefixIcon: Icon(icon, color: Colors.blue), hintText: hint, border: InputBorder.none, contentPadding: const EdgeInsets.all(16)),
      ),
    );
  }

  Future<void> _navigateToMusicSelection() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const MusicSelectionPage()));
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
        // Handle error
      }
    }
  }

  Widget _buildMusicSection() {
     return ListTile(
       tileColor: Colors.grey[50],
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[300]!)),
       leading: const Icon(Icons.music_note, color: Colors.purple),
       title: Text(_selectedMusicTitle ?? 'Add Music', style: const TextStyle(fontWeight: FontWeight.bold)),
       subtitle: Text(_selectedMusicArtist ?? 'Tap to select'),
       onTap: _navigateToMusicSelection,
       trailing: _selectedMusicUrl != null ? IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: (){
         setState(() {
           _selectedMusicUrl = null; _selectedMusicTitle = null; _selectedMusicArtist = null;
           _musicPlayer.stop();
         });
       }) : const Icon(Icons.chevron_right),
     );
  }

  Widget _buildMiniPlayer() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white), 
            onPressed: () => _isPlaying ? _musicPlayer.pause() : _musicPlayer.play()
          ),
          Expanded(child: Text(_selectedMusicTitle ?? '', style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}