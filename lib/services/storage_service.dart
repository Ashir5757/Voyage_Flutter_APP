import 'dart:convert';
import 'package:crypto/crypto.dart'; 
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract class StorageService {
  Future<List<String>> uploadImages(List<XFile> files, String postId);
  Future<void> deleteImage(String url);
}

class CloudinaryStorageService implements StorageService {
  final String _cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
  final String _apiKey = dotenv.env['CLOUDINARY_API_KEY'] ?? '';
  final String _apiSecret = dotenv.env['CLOUDINARY_API_SECRET'] ?? '';
  final String _uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '';

  @override
  Future<List<String>> uploadImages(List<XFile> files, String postId) async {
    final cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);
    List<String> urls = [];

    for (int i = 0; i < files.length; i++) {
      final path = files[i].path.toLowerCase();
      final bool isVideo = path.endsWith('.mp4') || path.endsWith('.mov') || path.endsWith('.avi');
      final String uniqueId = '${postId}_${DateTime.now().millisecondsSinceEpoch}_$i';

      try {
        final response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(
            files[i].path,
            folder: 'voyage/posts/$postId',
            publicId: uniqueId, 
            resourceType: isVideo ? CloudinaryResourceType.Video : CloudinaryResourceType.Image,
          ),
        );
        // Optimize images, leave videos raw
        if (!isVideo) {
          urls.add(response.secureUrl.replaceFirst('/upload/', '/upload/w_1200,h_800,c_fill,q_auto:good/'));
        } else {
          urls.add(response.secureUrl);
        }
      } catch (e) {
        print("Upload failed: $e");
      }
    }
    return urls;
  }

 @override
  Future<void> deleteImage(String url) async {
    if (url.isEmpty) return;

    // 1. DETECT RESOURCE TYPE
    // Cloudinary needs to know if we are deleting 'video' or 'image'
    // If you try to delete a video ID using the 'image' endpoint, it fails.
    final String resourceType = url.contains('/video/upload/') ? 'video' : 'image';

    // 2. EXTRACT ID
    final String publicId = _extractPublicId(url);
    if (publicId.isEmpty) return;

    print("🗑️ Cloudinary Delete: ($resourceType) $publicId");

    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // 3. SIGNATURE GENERATION
    // Important: 'invalidate' param must be included in signature if sent
    final String signatureData = "invalidate=true&public_id=$publicId&timestamp=$timestamp$_apiSecret";
    final String signature = sha1.convert(utf8.encode(signatureData)).toString();

    // 4. API CALL
    final deleteUrl = Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/destroy");

    try {
      final response = await http.post(deleteUrl, body: {
        'public_id': publicId,
        'timestamp': timestamp,
        'api_key': _apiKey,
        'signature': signature,
        'invalidate': 'true', // CLEARS CDN CACHE
      });

      if (response.statusCode == 200) {
        print("✅ Deleted successfully.");
      } else {
        print("⚠️ Delete failed: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      print("❌ Network error during delete: $e");
    }
  }

  String _extractPublicId(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final uploadIndex = segments.indexOf('upload');
      if (uploadIndex == -1) return "";

      List<String> validSegments = [];
      for (int i = uploadIndex + 1; i < segments.length; i++) {
        final seg = segments[i];
        // Skip version numbers (v12345) and transformations (w_500, etc.)
        if (RegExp(r'^v\d+$').hasMatch(seg)) continue;
        if (seg.contains('_') && (seg.startsWith('w_') || seg.startsWith('h_') || seg.startsWith('c_'))) continue;
        validSegments.add(seg);
      }

      String path = validSegments.join('/');
      // Remove extension
      if (path.contains('.')) path = path.substring(0, path.lastIndexOf('.'));
      
      return Uri.decodeFull(path);
    } catch (e) {
      return "";
    }
  }
}