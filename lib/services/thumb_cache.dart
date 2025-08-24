// lib/services/thumb_cache.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ThumbCache {
  /// Deletes all locally generated video thumbnails (video_thumbnail cache).
  static Future<void> clearLocalVideoThumbs() async {
    final tmpDir = await getTemporaryDirectory();
    final thumbsDir = Directory('${tmpDir.path}/video_thumbs');
    if (await thumbsDir.exists()) {
      await thumbsDir.delete(recursive: true);
    }
  }
}
