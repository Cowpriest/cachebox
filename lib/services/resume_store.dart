import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ResumeStore {
  static const _prefix = 'video_resume_v1';

  // Build a stable key per video. Prefer file id; fallback to URL.
  static String keyFor(
      {required String groupId, required String fileId, required String url}) {
    if (fileId.isNotEmpty) return '$_prefix:$groupId:$fileId';
    // fallback to URL if needed
    return '$_prefix:$groupId:$url';
  }

  /// Save position (in milliseconds) and optional duration (ms) for sanity checks.
  static Future<void> save({
    required String key,
    required int positionMs,
    int? durationMs,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'pos': positionMs,
      if (durationMs != null) 'dur': durationMs,
      'ts': DateTime.now()
          .millisecondsSinceEpoch, // for future pruning if desired
    });
    await sp.setString(key, payload);
  }

  /// Returns position in ms, or null if not found/invalid.
  static Future<int?> load(String key) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final pos = map['pos'] as int?;
      return (pos != null && pos >= 0) ? pos : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String key) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(key);
  }
}
