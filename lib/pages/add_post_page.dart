import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:tour/pages/music_selection_page.dart';
import 'package:tour/services/storage_service.dart';
import 'package:uuid/uuid.dart';

// Import the new widget
import 'package:tour/widgets/media_picker_section.dart';

class AddPostPage extends StatefulWidget {
  const AddPostPage({super.key});

  @override
  State<AddPostPage> createState() => _AddPostPageState();
}

class _AddPostPageState extends State<AddPostPage> {
  final StorageService _storage = CloudinaryStorageService();

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  // This list holds the data, but the Logic/UI is now in the separate file
  List<XFile> _selectedImages = []; 
  
  bool _isUploading = false;
  
  String? _selectedMusicUrl;
  String? _selectedMusicTitle;
  String? _selectedMusicArtist;
  
  final AudioPlayer _musicPlayer = AudioPlayer();
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _setupAudioListeners();
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

  // --- MAIN UPLOAD FUNCTION ---
  Future<void> _uploadPost() async {
    if (!mounted) return;
    
    // Validation
    if (_selectedImages.isEmpty) {
      _showSnackbar('Please select at least one image/video', Colors.red);
      return;
    }
    if (_locationController.text.isEmpty) {
      _showSnackbar('Please enter a location', Colors.red);
      return;
    }
    
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _showSnackbar('You must be logged in to post', Colors.red);
      return;
    }

    if (mounted) setState(() => _isUploading = true);

    try {
      final postId = _uuid.v4();
      final timestamp = DateTime.now();
      final formattedDate = DateFormat('yyyy-MM-dd – HH:mm').format(timestamp);
      
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      String userName = (userDoc.exists && userDoc.data() != null)
          ? (userDoc.data() as Map<String, dynamic>)['name'] ?? currentUser.displayName ?? 'Anonymous'
          : currentUser.displayName ?? 'Anonymous';

      // 1. UPLOAD IMAGES
      final List<String> imageUrls;
      try {
        imageUrls = await _storage.uploadImages(_selectedImages, postId);
      } catch (e) {
        if (mounted) {
          _showSnackbar('Failed to upload media: $e', Colors.red);
          setState(() => _isUploading = false);
        }
        return;
      }

      // 2. CREATE POST DATA
      final postData = {
        'postId': postId,
        'userId': currentUser.uid,
        'userName': userName,
        'userEmail': currentUser.email ?? '',
        'userPhoto': currentUser.photoURL ?? '',
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'imageUrls': imageUrls.toSet().toList(),
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
        'cloudinaryUpload': true,
      };

      // 3. SAVE TO FIRESTORE
      await _firestore.collection('posts').doc(postId).set(postData);
      
      await _firestore.collection('users').doc(currentUser.uid).set({
        'postsCount': FieldValue.increment(1),
        'lastPostDate': timestamp,
      }, SetOptions(merge: true));

      if (mounted) {
        _showSnackbar('Post shared successfully!', Colors.green);
        _clearForm();
        Navigator.pop(context);
      }

    } catch (e) {
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

  // --- UI WIDGETS ---

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
        title: const Text('Create Post', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: _isUploading ? null : _uploadPost,
              child: _isUploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('POST', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
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
                        Text(currentUser?.displayName ?? 'Traveler', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(currentUser?.email ?? 'User', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // --- HERE IS YOUR NEW SEPARATE COMPONENT ---
              MediaPickerSection(
                selectedImages: _selectedImages,
                onImagesChanged: (updatedList) {
                  setState(() {
                    _selectedImages = updatedList;
                  });
                },
              ),
              // -------------------------------------------
              
              const SizedBox(height: 24),
              _buildInputSection(
                icon: Icons.location_on_outlined,
                title: 'Location',
                hint: 'Where did you travel?',
                controller: _locationController,
              ),
              const SizedBox(height: 20),
              _buildInputSection(
                icon: Icons.description_outlined,
                title: 'Description',
                hint: 'Share your experience...',
                controller: _descriptionController,
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              _buildMusicSection(),
              if (_selectedMusicUrl != null) _buildMiniPlayer(),
              const SizedBox(height: 30),
              
              // Upload Button
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
                          Text('Uploading via Cloudinary', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                SizedBox(width: 12),
                                Text('Uploading...'),
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

  // ... (Keep _buildInputSection, _buildMusicSection, _buildMiniPlayer below)
  
  Widget _buildInputSection({required IconData icon, required String title, required String hint, required TextEditingController controller, int maxLines = 1}) {
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
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(hintText: hint, border: InputBorder.none, contentPadding: const EdgeInsets.all(16)),
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
              border: Border.all(color: _selectedMusicUrl != null ? Colors.purple : Colors.grey[300]!, width: _selectedMusicUrl != null ? 2 : 1),
            ),
            child: Row(
              children: [
                Icon(Icons.music_note, color: _selectedMusicUrl != null ? Colors.purple : Colors.grey, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: _selectedMusicUrl != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedMusicTitle ?? 'Unknown Title', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (_selectedMusicArtist != null)
                              Text(_selectedMusicArtist!, style: const TextStyle(fontSize: 14, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        )
                      : const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Add Music to Your Post', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('Tap to browse free music from Jamendo', style: TextStyle(fontSize: 14, color: Colors.grey)),
                          ],
                        ),
                ),
                Icon(Icons.chevron_right, color: _selectedMusicUrl != null ? Colors.purple : Colors.grey),
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
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))]),
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