// lib/services/file_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:cachebox/services/file_model.dart'; // your FileModel
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class FileService {
  static const String serverBase = 'http://cacheboxcapstone.duckdns.org:3000';

  /// Fetches the full metadata for every file in the group.
  static Future<List<FileModel>> listFiles(String groupId) async {
    final uri = Uri.parse('$serverBase/list/$groupId');
    final response = await http.get(uri);
    print('📤 FileService.listFiles → GET $uri');

    // http.Response res;
    // try {
    //   res = await http.get(uri);
    // } catch (e) {
    //   print('❌ FileService.listFiles HTTP error: $e');
    //   rethrow;
    // }

    // print('📥 FileService.listFiles response: '
    //     'status=${res.statusCode}, body=${res.body}');

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch files (${response.statusCode})');
    }
    final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
    return jsonList
        .map((e) => FileModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Uploads a file via multipart POST; then refresh your UI.
  static Future<void> uploadFile(String groupId) async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) {
      return;
    }
    final file = File(result.files.single.path!);
    final uri = Uri.parse('$serverBase/upload/$groupId');
    final req = http.MultipartRequest('POST', uri)
      ..fields['uploadedByUid'] = FirebaseAuth.instance.currentUser!.uid
      ..fields['uploadedByName'] =
          FirebaseAuth.instance.currentUser!.displayName ?? 'Unknown'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Upload failed: ${streamed.statusCode} $body');
    }
    // success
  }

  /// Delete both server‐side file and its metadata.
  static Future<void> deleteFile(String groupId, FileModel file) async {
    // adjust path if your API expects `id` or `fileName`
    final uri = Uri.parse('$serverBase/delete/$groupId/${file.id}');
    final response = await http.delete(uri);
    if (response.statusCode != 200) {
      throw Exception('Delete failed: ${response.statusCode}');
    }
  }

  /// Helper to open a file by URL.
  static String getFileUrl(String groupId, String filename) =>
      '$serverBase/files/$groupId/$filename';
}
