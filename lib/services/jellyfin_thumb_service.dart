// lib/services/jellyfin_thumb_service.dart
import 'dart:async';
import 'package:http/http.dart' as http;

class JellyfinThumbService {
  JellyfinThumbService._({required this.apiBase});

  static JellyfinThumbService? _instance;

  /// Call this once (e.g., from FilesScreen.initState).
  static JellyfinThumbService init({required String apiBase}) {
    _instance ??= JellyfinThumbService._(apiBase: apiBase);
    return _instance!;
  }

  /// Global accessor anywhere in the app (after init()).
  static JellyfinThumbService get I {
    final i = _instance;
    if (i == null) {
      throw StateError('JellyfinThumbService not initialized. Call init() first.');
    }
    return i;
  }

  final String apiBase;

  // In-memory cache (shared app-wide via singleton)
  final Map<String, String?> _cache = {};

  void clearCache({String? key}) {
    if (key == null) {
      _cache.clear();
    } else {
      _cache.remove(key);
    }
  }

  Future<String?> posterUrlForBasename(String basename, {String? folderHint}) async {
    final key = folderHint == null ? basename : '$basename|$folderHint';
    if (_cache.containsKey(key)) return _cache[key];

    final url = '$apiBase/api/jf/poster?name=${Uri.encodeQueryComponent(basename)}'
                '${folderHint != null ? '&hint=${Uri.encodeQueryComponent(folderHint)}' : ''}';

    try {
      final r = await http.head(Uri.parse(url)).timeout(const Duration(milliseconds: 800));
      final ok = r.statusCode == 200;
      _cache[key] = ok ? url : null;
      return _cache[key];
    } on TimeoutException {
      _cache[key] = null;
      return null;
    } catch (_) {
      _cache[key] = null;
      return null;
    }
  }
}
