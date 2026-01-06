import 'dart:io';
import 'dart:async'; // Required for Stream handling
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

    // Copy caption to clipboard immediately
    await Clipboard.setData(ClipboardData(text: shareText));

    // If no media, just share text
    if (mediaUrls.isEmpty) {
      await Share.share(shareText);
      return;
    }

    // --- SETUP FOR DOWNLOAD ---
    final client = http.Client(); // Create a client we can cancel
    final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    bool isCancelled = false;

    // 2. Show Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false, // User must click Cancel to exit
      builder: (dialogContext) {
        return WillPopScope(
          onWillPop: () async => false, // Disable back button closing
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Preparing Share...", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                // Animated Progress Bar
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, value, child) {
                    return Column(
                      children: [
                        LinearProgressIndicator(
                          value: value > 0 ? value : null, // Null = Indeterminate loading
                          backgroundColor: Colors.grey[200],
                          color: Colors.black,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          value > 0 ? "${(value * 100).toInt()}%" : "Downloading...",
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // --- CANCEL ACTION ---
                  isCancelled = true;
                  client.close(); // Kills the connection immediately
                  Navigator.of(dialogContext).pop(); // Close dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Share cancelled")),
                  );
                },
                child: const Text("Cancel", style: TextStyle(color: Colors.red)),
              )
            ],
          ),
        );
      },
    );

    try {
      XFile? fileToShare;

      // Get Original Quality URL
      String rawUrl = mediaUrls.first;
      String maxQualityUrl = _restoreOriginalQuality(rawUrl);

      // Naming
      final extension = _getFileExtension(maxQualityUrl);
      final fileName = 'share_temp_$postId.$extension';

      // 3. Download with Progress & Cancellation support
      fileToShare = await _downloadFileWithProgress(
        url: maxQualityUrl,
        filename: fileName,
        client: client,
        onProgress: (progress) {
          progressNotifier.value = progress;
        },
      );

      // Close the dialog if it's still open and we aren't cancelled
      if (!isCancelled && context.mounted) {
        Navigator.of(context).pop(); // Dismiss loading dialog
      }

      // 4. Share the Cached File
      if (fileToShare != null && !isCancelled) {
        await Share.shareXFiles([fileToShare], text: shareText);
      } 
      
    } catch (e) {
      // If error occurred (and wasn't just a cancel)
      if (!isCancelled && context.mounted) {
        Navigator.of(context).pop(); // Ensure dialog is closed
        debugPrint("Share failed: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not share this post")),
        );
      }
    } finally {
      client.close(); // Clean up client
    }
  }

  // --- HELPERS ---

  /// 🚀 Downloads file with progress updates and supports cancellation via [client]
  static Future<XFile?> _downloadFileWithProgress({
    required String url,
    required String filename,
    required http.Client client,
    required Function(double) onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final File file = File('${tempDir.path}/$filename');

      // Optional: Check cache (but we can't show progress for cached files easily, 
      // so for this UX we usually re-verify or just return 1.0 immediately)
      if (await file.exists()) {
        onProgress(1.0);
        return XFile(file.path);
      }

      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;
        
        final sink = file.openWrite();

        // Listen to the stream manually to calculate progress
        await response.stream.listen(
          (List<int> chunk) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            
            if (totalBytes > 0) {
              onProgress(receivedBytes / totalBytes);
            }
          },
          onDone: () async {
            await sink.close();
          },
          onError: (e) {
            sink.close();
            throw e; // Propagate cancellation error
          },
          cancelOnError: true,
        ).asFuture();

        return XFile(file.path);
      }
    } catch (e) {
      // If client.close() is called, an exception is thrown here.
      // We return null so the main function knows it failed/cancelled.
      return null;
    }
    return null;
  }

  static String _restoreOriginalQuality(String url) {
    if (!url.contains('cloudinary.com')) return url;
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
}