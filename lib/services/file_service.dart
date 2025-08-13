// lib/services/file_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'file_model.dart';

class FileService {
  /// Base URL of your file server.
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

  /// Original flat listing for backward compatibility.
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

  /// Folder-aware listing with path support and legacy fallback.
  Future<DirectoryListing> listEntries(
    String groupId, {
    String path = '',
    bool sync = false,
  }) async {
    final params = <String, String>{};
    if (path.isNotEmpty) params['path'] = path;
    if (sync) params['sync'] = 'true';

    final uri = Uri.parse('$baseUrl/list/$groupId').replace(
      queryParameters: params.isEmpty ? null : params,
    );
    final headers = await _authHeaders();
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('List failed (${res.statusCode}): ${res.body}');
    }
    final decoded = json.decode(res.body);

    // Preferred shape from server
    if (decoded is Map) { // Normalized Map branch
      final folders = (decoded['folders'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FolderModel.fromJson)
          .toList();
      final files = (decoded['files'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FileModel.fromJson)
          .toList();
      // Strip everything up to and including '<groupId>/' from folder paths and file storagePaths
      final marker = '\$groupId/';
      final normFolders = folders.map((f) {
        final idx = f.path.indexOf(marker);
        final newPath = idx >= 0 ? f.path.substring(idx + marker.length) : (f.path.startsWith('uploads/') ? f.path.substring(8) : f.path);
        final leaf = newPath.endsWith('/') ? newPath.substring(0, newPath.length - 1) : newPath;
        return FolderModel(name: leaf.split('/').isNotEmpty ? leaf.split('/').last : leaf, path: newPath.endsWith('/') ? newPath : newPath + '/');
      }).toList();
      final normFiles = files.map((f) {
        final sp = f.storagePath;
        final idx = sp.indexOf(marker);
        final newSp = idx >= 0 ? sp.substring(idx + marker.length) : (sp.startsWith('uploads/') ? sp.substring(8) : sp);
        return FileModel(
          id: f.id,
          fileName: f.fileName,
          fileUrl: f.fileUrl,
          uploadedByUid: f.uploadedByUid,
          uploadedByName: f.uploadedByName,
          storagePath: newSp,
          mimeType: f.mimeType,
        );
      }).toList();
      return DirectoryListing(folders: normFolders, files: normFiles);
    }

    // Legacy: flat list of files -> synthesize folders
    if (decoded is List) {
      final filesRaw = decoded
          .whereType<Map<String, dynamic>>()
          .map(FileModel.fromJson)
          .toList();

      // Normalize so the group's folder is logical root:
      // strip everything up to and including "<groupId>/", regardless of any "uploads/" or group name before it.
      final marker = '$groupId/';
      final files = filesRaw.map((f) {
        final sp = f.storagePath;
        final idx = sp.indexOf(marker);
        if (idx >= 0) {
          final after = sp.substring(idx + marker.length);
          return FileModel(
            id: f.id,
            fileName: f.fileName,
            fileUrl: f.fileUrl,
            uploadedByUid: f.uploadedByUid,
            uploadedByName: f.uploadedByName,
            storagePath: after,
            mimeType: f.mimeType,
          );
        }
        const up = 'uploads/';
        if (sp.startsWith(up)) {
          return FileModel(
            id: f.id,
            fileName: f.fileName,
            fileUrl: f.fileUrl,
            uploadedByUid: f.uploadedByUid,
            uploadedByName: f.uploadedByName,
            storagePath: sp.substring(up.length),
            mimeType: f.mimeType,
          );
        }
        return f;
      }).toList();

      if (path.isEmpty) {
        final Set<String> firstSegments = {};
        for (final f in files) {
          final sp = f.storagePath;
          final slash = sp.indexOf('/');
          if (slash > 0) firstSegments.add(sp.substring(0, slash + 1));
        }
        final folders = firstSegments.map((seg) {
          final name = seg.endsWith('/') ? seg.substring(0, seg.length - 1) : seg;
          return FolderModel(name: name, path: seg);
        }).toList();
        final rootFiles = files.where((f) => !f.storagePath.contains('/')).toList();
        return DirectoryListing(folders: folders, files: rootFiles);
      } else {
        // Inside a prefix: expose immediate subfolders + files
        final prefix = path.endsWith('/') ? path : '$path/';
        final subFolders = <String>{};
        final matchedFiles = <FileModel>[];
        for (final f in files) {
          if (f.storagePath.startsWith(prefix)) {
            final rest = f.storagePath.substring(prefix.length);
            final idx2 = rest.indexOf('/');
            if (idx2 >= 0) {
              final folderSeg = rest.substring(0, idx2 + 1);
              subFolders.add(prefix + folderSeg);
            } else {
              matchedFiles.add(f);
            }
          }
        }
        final folders = subFolders.map((full) {
          final parts = full.split('/');
          final name = (parts.isNotEmpty)
              ? (full.endsWith('/') && parts.length >= 2
                  ? parts[parts.length - 2]
                  : parts.last)
              : full;
          return FolderModel(name: name.replaceAll('/', ''), path: full);
        }).toList();
        return DirectoryListing(folders: folders, files: matchedFiles);
      }
    }

    throw Exception('Unexpected listEntries payload shape');
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
    req.fields['uploadedByName'] =
        user.displayName ?? user.email ?? user.uid;

    // Attach the file data
    if (filePath != null) {
      req.files.add(await http.MultipartFile.fromPath(
        'file',
        filePath,
        filename: filename, // may include folder prefix
      ));
    } else {
      req.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes!,
        filename: filename, // may include folder prefix
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
