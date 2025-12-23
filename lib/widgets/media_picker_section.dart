import 'dart:io';
import 'dart:async';
import 'dart:typed_data'; // Required for Uint8List
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart'; // 1. IMPORT THIS

class MediaPickerSection extends StatefulWidget {
  final List<XFile> selectedImages;
  final Function(List<XFile>) onImagesChanged;

  const MediaPickerSection({
    super.key,
    required this.selectedImages,
    required this.onImagesChanged,
  });

  @override
  State<MediaPickerSection> createState() => _MediaPickerSectionState();
}

class _MediaPickerSectionState extends State<MediaPickerSection> {
  // --- LIMITS ---
  final int _maxImageBytes = 10 * 1024 * 1024; // 10 MB
  final int _maxVideoBytes = 100 * 1024 * 1024; // 100 MB
  final Duration _maxVideoDuration = const Duration(minutes: 5); 

  final List<String> _allowedExtensions = ['jpg', 'jpeg', 'png', 'heic', 'webp', 'mp4', 'mov', 'avi', 'mkv'];

  // --- LOGIC ---

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultipleMedia(imageQuality: 80, requestFullMetadata: false);

    if (pickedFiles.isNotEmpty) {
      List<XFile> validFiles = [];
      bool invalidTypeFound = false;

      for (var file in pickedFiles) {
        if (!_isValidMediaType(file.path)) {
          invalidTypeFound = true;
          continue; 
        }
        if (await _validateFile(file)) {
          validFiles.add(file);
        }
      }

      if (invalidTypeFound) _showError("Only images and videos are allowed.");
      
      if (validFiles.isNotEmpty) {
        final updatedList = List<XFile>.from(widget.selectedImages)..addAll(validFiles);
        widget.onImagesChanged(updatedList);
      }
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    
    if (pickedFile != null && await _validateFile(pickedFile)) {
      final updatedList = List<XFile>.from(widget.selectedImages)..add(pickedFile);
      widget.onImagesChanged(updatedList);
    }
  }

  // --- VALIDATORS ---

  bool _isValidMediaType(String path) {
    final extension = path.split('.').last.toLowerCase();
    return _allowedExtensions.contains(extension);
  }

  bool _isVideo(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi') || lower.endsWith('.mkv');
  }

  Future<bool> _validateFile(XFile file) async {
    final int size = await file.length();
    final bool isVideoFile = _isVideo(file.path);

    if (isVideoFile && size > _maxVideoBytes) {
      _showError("Video too large. Max 100MB.");
      return false;
    } else if (!isVideoFile && size > _maxImageBytes) {
      _showError("Image too large. Max 10MB.");
      return false;
    }

    if (isVideoFile) {
      // We create a temporary controller just to check duration, then dispose immediately
      VideoPlayerController? testController;
      try {
        testController = VideoPlayerController.file(File(file.path));
        await testController.initialize();
        if (testController.value.duration > _maxVideoDuration) {
          _showError("Video must be shorter than 5 minutes.");
          await testController.dispose();
          return false;
        }
        await testController.dispose();
      } catch (e) {
        return false;
      }
    }
    return true;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [const Icon(Icons.error_outline, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text(message))]),
        backgroundColor: Colors.red[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _removeFile(int index) {
    final updatedList = List<XFile>.from(widget.selectedImages)..removeAt(index);
    widget.onImagesChanged(updatedList);
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.perm_media, color: Colors.blue),
            const SizedBox(width: 8),
            Text('Media Gallery', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
            const SizedBox(width: 8),
            Text('(${widget.selectedImages.length})', style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildButton(Icons.photo_library, 'Gallery', Colors.blue, _pickImages)),
            const SizedBox(width: 12),
            Expanded(child: _buildButton(Icons.camera_alt, 'Camera', Colors.green, _takePhoto)),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.selectedImages.isNotEmpty)
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.selectedImages.length,
              itemBuilder: (context, index) {
                return _MediaThumbnailItem(
                  file: File(widget.selectedImages[index].path),
                  onRemove: () => _removeFile(index),
                );
              },
            ),
          )
        else 
          _buildEmptyState(),
      ],
    );
  }

  Widget _buildButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color.withOpacity(0.9),
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity, height: 150,
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[300]!)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text('Add Photos & Videos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

// --- OPTIMIZED THUMBNAIL WIDGET ---
class _MediaThumbnailItem extends StatefulWidget {
  final File file;
  final VoidCallback onRemove;
  const _MediaThumbnailItem({required this.file, required this.onRemove});

  @override
  State<_MediaThumbnailItem> createState() => _MediaThumbnailItemState();
}

class _MediaThumbnailItemState extends State<_MediaThumbnailItem> {
  Uint8List? _thumbnailBytes;
  bool _isLoading = true;

  bool get _isVideo => widget.file.path.toLowerCase().endsWith('.mp4') || 
                       widget.file.path.toLowerCase().endsWith('.mov') ||
                       widget.file.path.toLowerCase().endsWith('.avi') ||
                       widget.file.path.toLowerCase().endsWith('.mkv');

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      _generateThumbnail();
    } else {
      _isLoading = false;
    }
  }

  // 🚀 CRITICAL OPTIMIZATION: Generate static image instead of loading video
  Future<void> _generateThumbnail() async {
    try {
      final uint8list = await VideoThumbnail.thumbnailData(
        video: widget.file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200, // Keep resolution low for thumbnails to save RAM
        quality: 50,
      );
      if (mounted) {
        setState(() {
          _thumbnailBytes = uint8list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openFullScreen() {
    if (_isVideo) {
      // We only initialize the heavy VideoPlayer when user CLICKS play
      final controller = VideoPlayerController.file(widget.file);
      controller.initialize().then((_) {
        Navigator.push(
          context, 
          MaterialPageRoute(builder: (_) => _ProfessionalVideoPlayer(controller: controller))
        ).then((_) {
          // Dispose immediately when closed to free up hardware resources
          controller.dispose(); 
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140, margin: const EdgeInsets.only(right: 12),
      child: Stack(
        children: [
          // 1. THUMBNAIL CONTENT
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox.expand(
              child: _buildContent(),
            ),
          ),
          
          // 2. REMOVE BUTTON
          Positioned(top: 8, right: 8, child: GestureDetector(onTap: widget.onRemove, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
          
          // 3. PLAY ICON (Only for videos)
          if (_isVideo) 
            Center(child: GestureDetector(onTap: _openFullScreen, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const Icon(Icons.play_arrow, color: Colors.white, size: 24)))),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (!_isVideo) {
      return Image.file(widget.file, fit: BoxFit.cover);
    }
    
    if (_isLoading) {
      return Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }

    if (_thumbnailBytes != null) {
      return Image.memory(_thumbnailBytes!, fit: BoxFit.cover);
    }

    return Container(color: Colors.black, child: const Icon(Icons.error, color: Colors.white));
  }
}

// --- PROFESSIONAL FULL SCREEN PLAYER ---
class _ProfessionalVideoPlayer extends StatefulWidget {
  final VideoPlayerController controller;
  const _ProfessionalVideoPlayer({required this.controller});

  @override
  State<_ProfessionalVideoPlayer> createState() => _ProfessionalVideoPlayerState();
}

class _ProfessionalVideoPlayerState extends State<_ProfessionalVideoPlayer> {
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.play();
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$min:$sec";
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. VIDEO
              Center(
                child: AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
              ),

              // 2. CONTROLS OVERLAY
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  color: Colors.black.withOpacity(0.3), 
                  child: Stack(
                    children: [
                      // CLOSE
                      Positioned(
                        top: 20, left: 20,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      // PLAY/PAUSE
                      Center(
                        child: IconButton(
                          iconSize: 64,
                          icon: Icon(
                            widget.controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              widget.controller.value.isPlaying ? widget.controller.pause() : widget.controller.play();
                              _startHideTimer();
                            });
                          },
                        ),
                      ),
                      // SLIDER
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
                          ),
                          child: Column(
                            children: [
                              ValueListenableBuilder(
                                valueListenable: widget.controller,
                                builder: (context, VideoPlayerValue value, child) {
                                  return Row(
                                    children: [
                                      Text(_formatDuration(value.position), style: const TextStyle(color: Colors.white)),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderThemeData(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 12), activeTrackColor: Colors.blueAccent, thumbColor: Colors.white),
                                          child: Slider(
                                            value: value.position.inSeconds.toDouble(),
                                            min: 0,
                                            max: value.duration.inSeconds.toDouble(),
                                            onChanged: (val) {
                                              _startHideTimer();
                                              widget.controller.seekTo(Duration(seconds: val.toInt()));
                                            },
                                          ),
                                        ),
                                      ),
                                      Text(_formatDuration(value.duration), style: const TextStyle(color: Colors.white)),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}