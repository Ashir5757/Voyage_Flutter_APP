import 'dart:convert';
import 'package:crypto/crypto.dart'; // You'll need the 'crypto' package in pubspec
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
    for (var file in files) {
      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(file.path, folder: 'voyage/posts/$postId'),
      );
      urls.add(response.secureUrl);
    }
    return urls;
  }

  @override
  Future<void> deleteImage(String url) async {
    // 1. Extract Public ID from the URL
    // Example: https://res.cloudinary.com/demo/image/upload/v1234/voyage/posts/id.jpg -> voyage/posts/id
    final String publicId = _extractPublicId(url);

    // 2. Generate Timestamp
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // 3. Create Signature (SHA-1)
    // Cloudinary requires: sha1("public_id=xxx&timestamp=xxxYOUR_API_SECRET")
    final String signatureData = "public_id=$publicId&timestamp=$timestamp$_apiSecret";
    final String signature = sha1.convert(utf8.encode(signatureData)).toString();

    // 4. Call Cloudinary Destroy API
    final deleteUrl = Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/image/destroy");
    
    try {
      final response = await http.post(deleteUrl, body: {
        'public_id': publicId,
        'timestamp': timestamp,
        'api_key': _apiKey,
        'signature': signature,
      });
      
      if (response.statusCode == 200) {
        print("Successfully deleted from Cloudinary: $publicId");
      }
    } catch (e) {
      print("Error deleting from Cloudinary: $e");
    }
  }

  String _extractPublicId(String url) {
    // Basic logic to get the path between 'upload/' and the file extension
    final parts = url.split('upload/');
    if (parts.length < 2) return "";
    final pathWithExtension = parts[1].split('/').sublist(1).join('/'); // Skips version number (v12345)
    return pathWithExtension.split('.').first;
  }
}