import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:cross_file/cross_file.dart';

class ShareService {
  
  static Future<void> sharePost({
    required BuildContext context,
    required Map<String, dynamic> post,
    required String postId,
    required List<String> mediaUrls,
  }) async {
    
    // 1. Prepare Text
    final userName = post['userName'] ?? 'a traveler';
    final location = post['location'] != null ? '📍 ${post['location']}' : '';
    final description = post['description'] ?? '';
    final String shareText = '$description\n\n👤 Posted by: $userName\n$location';

    // 2. Notify User: "Preparing" instead of "Downloading"
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preparing to share...'),
        duration: Duration(seconds: 1),
        backgroundColor: Colors.black87,
      ),
    );

    try {
      // Copy caption to clipboard (Standard IG behavior)
      await Clipboard.setData(ClipboardData(text: shareText));

      XFile? fileToShare;
      
      if (mediaUrls.isNotEmpty) {
        // Get Original Quality URL (Strip Cloudinary compression)
        String rawUrl = mediaUrls.first;
        String maxQualityUrl = _restoreOriginalQuality(rawUrl);

        // Naming the temp file
        final extension = _getFileExtension(maxQualityUrl);
        final fileName = 'temp_share_$postId.$extension';

        // 3. CACHE the file (Invisible to Gallery)
        fileToShare = await _cacheFileForSharing(maxQualityUrl, fileName);
      }

      // 4. Share the Cached File
      if (fileToShare != null) {
        // This opens the system share sheet with the File + Text
        await Share.shareXFiles([fileToShare], text: shareText);
      } else {
        // Fallback: Share just text if media fails
        await Share.share(shareText);
      }
      
    } catch (e) {
      debugPrint("Share failed: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not share this post")),
        );
      }
    }
  }

  // --- HELPERS ---

  /// 🚀 Removes Cloudinary limits to get FULL HD quality
  static String _restoreOriginalQuality(String url) {
    if (!url.contains('cloudinary.com')) return url;
    // Remove transformations like /w_800,q_auto/ to get original file
    final regex = RegExp(r'\/upload\/[^v]+\/');
    if (regex.hasMatch(url)) {
      return url.replaceFirst(regex, '/upload/');
    }
    return url;
  }

  static bool _isVideo(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi') || lower.contains('/video/');
  }

  static String _getFileExtension(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      if (path.contains('.')) return path.split('.').last;
    } catch (e) { /* ignore */ }
    return _isVideo(url) ? 'mp4' : 'jpg';
  }

  /// ⚡ STREAMS file to "Temporary Cache" (Not Gallery)
  /// This is memory safe and cleans up automatically.
  static Future<XFile?> _cacheFileForSharing(String url, String filename) async {
    try {
      // getTemporaryDirectory() = The "Hidden Cache" folder.
      // Files here are NOT visible in the Gallery and are deleted by the OS automatically.
      final tempDir = await getTemporaryDirectory();
      final File file = File('${tempDir.path}/$filename');

      // Check if we already cached it recently to save bandwidth
      if (await file.exists()) {
        return XFile(file.path);
      }

      // Stream download (No RAM crash)
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        final sink = file.openWrite();
        await response.stream.pipe(sink);
        await sink.close();
        return XFile(file.path);
      }
    } catch (e) {
      debugPrint('Cache error: $e');
    }
    return null;
  }
}