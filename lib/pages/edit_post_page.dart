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
import 'package:tour/services/cloudinary_service.dart'; // <--- IMPORT THIS
import 'package:tour/widgets/editable_media_section.dart';

class EditPostPage extends StatefulWidget {
  final Map<String, dynamic> currentData; 
  final String postId;

  const EditPostPage({super.key, required this.currentData, required this.postId});

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  // Services
  final StorageService _storage = CloudinaryStorageService();
  final CloudinaryService _videoService = CloudinaryService(); // <--- NEW SERVICE

  late TextEditingController _locationController;
  late TextEditingController _descriptionController;
  
  // Lists
  List<String> _originalUrls = [];
  List<String> _existingImageUrls = [];
  List<XFile> _newImages = []; 

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

    if (widget.currentData['imageUrls'] != null) {
      _existingImageUrls = List<String>.from(widget.currentData['imageUrls']);
    } else if (widget.currentData['image'] != null) {
      _existingImageUrls = [widget.currentData['image']];
    }
    
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
    setState(() => _existingImageUrls.removeAt(index));
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
  }

  bool _isVideo(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi') || lower.endsWith('.mkv');
  }

  // ---------------------------------------------------------
  // ⚡ UPDATED: WITH PROGRESS DIALOG & VIDEO SUPPORT
  // ---------------------------------------------------------
  Future<void> _updatePost() async {
    if (!mounted) return;
    
    if (_existingImageUrls.isEmpty && _newImages.isEmpty) {
      _showSnackbar('Post must have at least one photo or video', Colors.red);
      return;
    }

    // 1. Setup Progress Notifier for the Dialog
    ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    ValueNotifier<String> statusNotifier = ValueNotifier("Preparing...");

    // 2. Show the Dialog
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, status, _) => Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value > 0 ? value : null, 
                    backgroundColor: Colors.grey[200],
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, value, _) => Text("${(value * 100).toInt()}%"),
                ),
              ],
            ),
          ),
        );
      },
    );

    setState(() => _isUpdating = true);

    try {
      List<String> newUploadedUrls = [];

      // 3. UPLOAD NEW FILES ONE BY ONE
      // We do this loop manually to track progress, especially for videos
      int totalFiles = _newImages.length;
      
      for (int i = 0; i < totalFiles; i++) {
        XFile file = _newImages[i];
        bool isVideoFile = _isVideo(file.path);

        statusNotifier.value = "Uploading ${i + 1} of $totalFiles...";
        
        String? uploadedUrl;

        if (isVideoFile) {
          // --- VIDEO UPLOAD (With Progress) ---
          uploadedUrl = await _videoService.uploadVideo(
            File(file.path), 
            (fileProgress) {
              // Calculate overall progress: 
              // (Completed Files + Current File Progress) / Total Files
              double overall = (i + fileProgress) / totalFiles;
              progressNotifier.value = overall;
            }
          );
        } else {
          // --- IMAGE UPLOAD (Fast, standard) ---
          // Use standard service, but wrap in list to reuse existing method
          // Or optimize by uploading individually if your service allows.
          // Here assuming _storage.uploadImages takes list, we pass single item list.
          List<String> res = await _storage.uploadImages([file], widget.postId);
          if (res.isNotEmpty) uploadedUrl = res.first;
          
          // Jump progress for images (instant)
          progressNotifier.value = (i + 1) / totalFiles;
        }

        if (uploadedUrl != null) {
          newUploadedUrls.add(uploadedUrl);
        }
      }

      statusNotifier.value = "Saving changes...";

      // 4. MERGE & CLEANUP
      final List<String> finalImageUrls = [..._existingImageUrls, ...newUploadedUrls];

      final List<String> urlsToDelete = _originalUrls
          .where((url) => !finalImageUrls.contains(url))
          .toList();

      // 5. FIRESTORE UPDATE
      await Future.wait([
        FirebaseFirestore.instance.collection('posts').doc(widget.postId).update({
          'location': _locationController.text.trim(),
          'description': _descriptionController.text.trim(),
          'imageUrls': finalImageUrls,
          'image': finalImageUrls.isNotEmpty ? finalImageUrls.first : null,
          'musicUrl': _selectedMusicUrl,
          'musicTitle': _selectedMusicTitle,
          'musicArtist': _selectedMusicArtist,
        }),
        _performCleanup(urlsToDelete),
      ]);

      if (mounted) {
        Navigator.pop(context); // Close Progress Dialog
        Navigator.pop(context, true); // Close Edit Page
        _showSnackbar('Voyage updated successfully!', Colors.green);
      }
    } catch (e) {
      debugPrint("Update Error: $e");
      if (mounted) {
        Navigator.pop(context); // Close Progress Dialog on error
        _showSnackbar('Failed to update. Please try again.', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _performCleanup(List<String> urls) async {
    for (String url in urls) {
      try {
        await _storage.deleteImage(url);
        await CachedNetworkImageProvider(url).evict();
      } catch (e) {
        debugPrint("Cleanup warning: $e");
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
            child: Text('SAVE', style: TextStyle(color: _isUpdating ? Colors.grey : Colors.blue, fontWeight: FontWeight.bold)),
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

              EditableMediaSection(
                existingUrls: _existingImageUrls,
                newFiles: _newImages,
                onNewFilesChanged: (List<XFile> updatedFiles) {
                  setState(() => _newImages = updatedFiles);
                },
                onRemoveExisting: _removeExistingImage,
                onRemoveNew: _removeNewImage,
              ),

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
                  label: const Text('Update Voyage'),
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