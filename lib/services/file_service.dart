// lib/services/file_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'file_model.dart';

class FileService {
  /// Base URL of your file server; override if you need staging vs prod.
  final String baseUrl;

  FileService([this.baseUrl = 'http://cacheboxcapstone.duckdns.org:3000']);

  /// Lists the files for [groupId]. If [sync] is true, calls
  /// GET /list/:groupId?sync=true to reconcile stray files.
  Future<List<FileModel>> listFiles(String groupId, {bool sync = false}) async {
    final syncParam = sync ? '?sync=true' : '';
    final uri = Uri.parse('$baseUrl/list/$groupId$syncParam');
    print('📤 GET $uri');
    final res = await http.get(uri);
    print('📥 status=${res.statusCode}, body=${res.body}');
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch files (${res.statusCode}): ${res.body}');
    }
    final List data = json.decode(res.body) as List;
    return data
        .map((e) => FileModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Uploads a single file for [groupId]. The caller must have
  /// already picked a file and provided its path.
  Future<FileModel> uploadFile(
      String groupId, String filePath, String fieldName) async {
    final uri = Uri.parse('$baseUrl/upload/$groupId');
    print('📤 POST $uri (multipart)');
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath(fieldName, filePath));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    print('📥 status=${res.statusCode}, body=${res.body}');
    if (res.statusCode != 200) {
      throw Exception('Upload failed (${res.statusCode}): ${res.body}');
    }
    return FileModel.fromJson(json.decode(res.body) as Map<String, dynamic>);
  }

  /// Deletes the file with [fileId] in [groupId].
  Future<void> deleteFile(String groupId, FileModel file) async {
    final uri = Uri.parse('$baseUrl/delete/$groupId/${file.id}');
    print('📤 DELETE $uri');
    final res = await http.delete(uri);
    print('📥 status=${res.statusCode}, body=${res.body}');
    if (res.statusCode != 200) {
      throw Exception('Delete failed (${res.statusCode}): ${res.body}');
    }
  }
}
