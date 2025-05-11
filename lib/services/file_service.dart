// lib/services/file_service.dart

import 'dart:convert';
import 'dart:typed_data'; // ← for Uint8List
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'file_model.dart';

class FileService {
  /// Base URL of your file server; override for staging vs. prod if you like.
  final String baseUrl;
  FileService({this.baseUrl = 'http://cacheboxcapstone.duckdns.org:3000'});

  /// Grabs a fresh Firebase ID token and returns the headers map.
  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
  }

  /// List files in a group (optionally syncs stray disk files back into metadata.json).
  Future<List<FileModel>> listFiles(String groupId, {bool sync = false}) async {
    final syncParam = sync ? '?sync=true' : '';
    final uri = Uri.parse('$baseUrl/list/$groupId$syncParam');
    final headers = await _authHeaders();
    final res = await http.get(uri, headers: headers);

    if (res.statusCode != 200) {
      throw Exception('List failed (${res.statusCode}): ${res.body}');
    }
    final List<dynamic> jsonList = json.decode(res.body);
    return jsonList.map((j) => FileModel.fromJson(j)).toList();
  }

  /// Uploads a file by either path or bytes. You must supply `filename`.
  Future<FileModel> uploadFile(
    String groupId, {
    String? filePath,
    Uint8List? fileBytes,
    required String filename,
  }) async {
    if (filePath == null && fileBytes == null) {
      throw ArgumentError('Either filePath or fileBytes must be provided');
    }

    final uri = Uri.parse('$baseUrl/upload/$groupId');
    final headers = await _authHeaders();

    final req = http.MultipartRequest('POST', uri)..headers.addAll(headers);

    // Stamp uploader info from the verified token
    final user = FirebaseAuth.instance.currentUser!;
    req.fields['uploadedByUid'] = user.uid;
    req.fields['uploadedByName'] = user.displayName ?? user.email ?? user.uid;

    // Attach the file data
    if (filePath != null) {
      req.files.add(await http.MultipartFile.fromPath(
        'file',
        filePath,
        filename: filename,
      ));
    } else {
      req.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes!,
        filename: filename,
      ));
    }

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Upload failed (${streamed.statusCode}): $body');
    }
    return FileModel.fromJson(json.decode(body));
  }

  /// Deletes by the file’s UUID (string).
  Future<void> deleteFile(String groupId, String fileId) async {
    final uri = Uri.parse('$baseUrl/delete/$groupId/$fileId');
    final headers = await _authHeaders();

    final res = await http.delete(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Delete failed (${res.statusCode}): ${res.body}');
    }
  }
}
