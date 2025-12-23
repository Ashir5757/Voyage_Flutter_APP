import 'dart:io';
import 'dart:async';
import 'dart:typed_data'; // Required for Uint8List
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_thumbnail/video_thumbnail.dart'; // 1. IMPORT THIS

class EditableMediaSection extends StatefulWidget {
  final List<String> existingUrls;
  final List<XFile> newFiles;
  
  final Function(List<XFile>) onNewFilesChanged;
  final Function(int) onRemoveExisting;
  final Function(int) onRemoveNew;

  const EditableMediaSection({
    super.key,
    required this.existingUrls,
    required this.newFiles,
    required this.onNewFilesChanged,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  @override
  State<EditableMediaSection> createState() => _EditableMediaSectionState();
}

class _EditableMediaSectionState extends State<EditableMediaSection> {
  // --- LIMITS ---
  final int _maxImageBytes = 10 * 1024 * 1024; // 10 MB
  final int _maxVideoBytes = 100 * 1024 * 1024; // 100 MB
  final Duration _maxVideoDuration = const Duration(minutes: 5); 

  final List<String> _allowedExtensions = ['jpg', 'jpeg', 'png', 'heic', 'webp', 'mp4', 'mov', 'avi', 'mkv'];

  // --- PICKING LOGIC ---

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
        final updatedList = List<XFile>.from(widget.newFiles)..addAll(validFiles);
        widget.onNewFilesChanged(updatedList);
      }
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    
    if (pickedFile != null && await _validateFile(pickedFile)) {
      final updatedList = List<XFile>.from(widget.newFiles)..add(pickedFile);
      widget.onNewFilesChanged(updatedList);
    }
  }

  // --- VALIDATION ---

  bool _isValidMediaType(String path) {
    final extension = path.split('.').last.toLowerCase();
    return _allowedExtensions.contains(extension);
  }

  bool _isVideo(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi') || lower.contains('/video/');
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
      // Create temp controller just for validation, dispose immediately
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
      SnackBar(content: Text(message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.perm_media, color: Colors.blue),
                const SizedBox(width: 8),
                Text('Media Gallery', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                const SizedBox(width: 8),
                Text('(${widget.existingUrls.length + widget.newFiles.length})', style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
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
        if (widget.existingUrls.isNotEmpty || widget.newFiles.isNotEmpty)
          SizedBox(
            height: 180,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // 1. EXISTING (Network)
                ...widget.existingUrls.asMap().entries.map((entry) {
                  return _NetworkThumbnailItem(
                    url: entry.value,
                    onRemove: () => widget.onRemoveExisting(entry.key),
                  );
                }),
                // 2. NEW (Local File)
                ...widget.newFiles.asMap().entries.map((entry) {
                  return _LocalThumbnailItem(
                    file: File(entry.value.path),
                    onRemove: () => widget.onRemoveNew(entry.key),
                  );
                }),
              ],
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

// =========================================================
// SHARED BASE THUMBNAIL (For consistent UI)
// =========================================================
class _ThumbnailBase extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  final bool isVideo;
  final bool isNew;
  final VoidCallback? onPlay;

  const _ThumbnailBase({
    required this.child,
    required this.onRemove,
    this.isVideo = false,
    this.isNew = false,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140, 
      margin: const EdgeInsets.only(right: 12),
      child: Stack(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox.expand(child: child)),
          
          // Remove Button
          Positioned(top: 8, right: 8, child: GestureDetector(onTap: onRemove, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
          
          // Play Button
          if (isVideo) Center(child: GestureDetector(onTap: onPlay, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const Icon(Icons.play_arrow, color: Colors.white, size: 24)))),
          
          // New Label
          if (isNew) Positioned(bottom: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(4)), child: const Text("NEW", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }
}

// =========================================================
// WIDGET 1: LOCAL THUMBNAIL (Files from Phone)
// =========================================================
class _LocalThumbnailItem extends StatefulWidget {
  final File file;
  final VoidCallback onRemove;
  const _LocalThumbnailItem({required this.file, required this.onRemove});

  @override
  State<_LocalThumbnailItem> createState() => _LocalThumbnailItemState();
}

class _LocalThumbnailItemState extends State<_LocalThumbnailItem> {
  Uint8List? _thumbnailBytes;
  bool _isLoading = true;

  bool get _isVideo {
    final path = widget.file.path.toLowerCase();
    return path.endsWith('.mp4') || path.endsWith('.mov') || path.endsWith('.avi') || path.endsWith('.mkv');
  }

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      _generateThumbnail();
    } else {
      _isLoading = false;
    }
  }

  // 🚀 OPTIMIZATION: Generate static image (50KB) instead of VideoPlayer (50MB)
  Future<void> _generateThumbnail() async {
    try {
      final uint8list = await VideoThumbnail.thumbnailData(
        video: widget.file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200, // Small size for List View
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
      // 🚀 Only Init VideoPlayer on Play Tap
      final controller = VideoPlayerController.file(widget.file);
      controller.initialize().then((_) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => _ProfessionalVideoPlayer(controller: controller)))
          .then((_) => controller.dispose()); // Dispose immediately on back
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    
    if (!_isVideo) {
      // 🚀 OPTIMIZATION: Resize local images too (saves RAM)
      content = Image.file(widget.file, fit: BoxFit.cover, cacheWidth: 300);
    } else if (_isLoading) {
      content = Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (_thumbnailBytes != null) {
      content = Image.memory(_thumbnailBytes!, fit: BoxFit.cover);
    } else {
      content = Container(color: Colors.black, child: const Icon(Icons.error, color: Colors.white));
    }

    return _ThumbnailBase(
      isNew: true,
      isVideo: _isVideo,
      onRemove: widget.onRemove,
      onPlay: _openFullScreen,
      child: content,
    );
  }
}

// =========================================================
// WIDGET 2: NETWORK THUMBNAIL (Existing URLs)
// =========================================================
class _NetworkThumbnailItem extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;
  const _NetworkThumbnailItem({required this.url, required this.onRemove});

  bool get _isVideo => url.contains('/video/') || url.endsWith('.mp4');

  String get _thumbnailUrl {
    if (url.contains('cloudinary.com') && _isVideo) {
      return url.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.jpg');
    }
    return url;
  }

  void _openFullScreen(BuildContext context) {
    // 🚀 Only Init VideoPlayer on Play Tap
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    controller.initialize().then((_) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => _ProfessionalVideoPlayer(controller: controller)))
        .then((_) => controller.dispose());
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ThumbnailBase(
      isNew: false,
      isVideo: _isVideo,
      onRemove: onRemove,
      onPlay: () => _openFullScreen(context),
      child: CachedNetworkImage(
        imageUrl: _thumbnailUrl,
        fit: BoxFit.cover,
        memCacheWidth: 300, // 🚀 OPTIMIZATION: MemCache
        placeholder: (c, u) => Container(color: Colors.grey[200]),
        errorWidget: (c, u, e) => Container(color: Colors.grey[300], child: const Icon(Icons.broken_image)),
      ),
    );
  }
}

// =========================================================
// WIDGET 3: SHARED FULL SCREEN PLAYER
// =========================================================
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

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.pause();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$min:$sec";
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
              Center(
                child: AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
              ),
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Stack(
                    children: [
                      Positioned(top: 20, left: 20, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28), onPressed: () => Navigator.pop(context))),
                      Center(child: IconButton(iconSize: 64, icon: Icon(widget.controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white), onPressed: () { setState(() { widget.controller.value.isPlaying ? widget.controller.pause() : widget.controller.play(); _startHideTimer(); }); })),
                      Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])), child: Column(mainAxisSize: MainAxisSize.min, children: [ValueListenableBuilder(valueListenable: widget.controller, builder: (context, VideoPlayerValue value, child) { return Row(children: [Text(_formatDuration(value.position), style: const TextStyle(color: Colors.white)), Expanded(child: SliderTheme(data: SliderThemeData(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 12), activeTrackColor: Colors.blueAccent, inactiveTrackColor: Colors.white24, thumbColor: Colors.white), child: Slider(value: value.position.inSeconds.toDouble(), min: 0, max: value.duration.inSeconds.toDouble(), onChanged: (val) { _startHideTimer(); widget.controller.seekTo(Duration(seconds: val.toInt())); }))), Text(_formatDuration(value.duration), style: const TextStyle(color: Colors.white))]); })]))),
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