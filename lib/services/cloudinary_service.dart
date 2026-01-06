import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CloudinaryService {
  Future<String?> uploadVideo(File videoFile, Function(double) onProgress) async {
    // 1. Load keys from .env
    final String? cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'];
    final String? uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'];

    if (cloudName == null || uploadPreset == null) {
      print("ERROR: Cloudinary keys not found in .env file");
      return null;
    }

    String url = "https://api.cloudinary.com/v1_1/$cloudName/video/upload";

    try {
      // 2. Prepare Form Data
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(videoFile.path),
        "upload_preset": uploadPreset,
        "resource_type": "video",
      });

      // 3. Upload with Dio to track progress
      Response response = await Dio().post(
        url,
        data: formData,
        onSendProgress: (int sent, int total) {
          double progress = sent / total;
          onProgress(progress); // Update the UI
        },
      );

      if (response.statusCode == 200) {
        return response.data['secure_url'];
      }
    } catch (e) {
      print("Upload Error: $e");
    }
    return null;
  }
}