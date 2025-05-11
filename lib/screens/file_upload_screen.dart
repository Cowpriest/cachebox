// lib/screens/file_upload_screen.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// ← Import wherever you've declared your host/port once:
// e.g. lib/services/file_service.dart
import '../services/file_service.dart';

class FileUploadScreen extends StatefulWidget {
  final String groupId;
  const FileUploadScreen({Key? key, required this.groupId}) : super(key: key);

  @override
  _FileUploadScreenState createState() => _FileUploadScreenState();
}

class _FileUploadScreenState extends State<FileUploadScreen> {
  bool _uploading = false;
  String _uploadStatus = '';
  double _uploadProgress = 0.0;

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null) {
      print("⚠ No file selected.");
      return;
    }

    setState(() {
      _uploading = true;
      _uploadStatus = "Uploading...";
      _uploadProgress = 0.0;
    });

    final file = result.files.single;
    Uint8List? bytes = file.bytes;
    final path = file.path;

    // Load bytes on physical devices if needed
    if (bytes == null && path != null) {
      try {
        bytes = await File(path).readAsBytes();
      } catch (e) {
        print("❌ Error reading bytes: $e");
        setState(() {
          _uploading = false;
          _uploadStatus = "Failed reading file.";
        });
        return;
      }
    }
    if (bytes == null) {
      setState(() {
        _uploading = false;
        _uploadStatus = "No data to upload.";
      });
      return;
    }

    // 1) Upload raw bytes to Firebase Storage so your Node server can serve them
    final storageRef = FirebaseStorage.instance
        .ref('groups/${widget.groupId}/files/${file.name}');
    final uploadTask = storageRef.putData(bytes);

    uploadTask.snapshotEvents.listen((snap) {
      final progress = snap.bytesTransferred / snap.totalBytes;
      setState(() => _uploadProgress = progress);
      print("📈 ${(progress * 100).toStringAsFixed(0)}%");
    });

    String downloadUrl;
    try {
      await uploadTask;
      downloadUrl = await storageRef.getDownloadURL();
      print("🔗 Download URL: $downloadUrl");
    } catch (e) {
      print("❌ Storage upload failed: $e");
      setState(() {
        _uploading = false;
        _uploadStatus = "Storage upload failed.";
      });
      return;
    }

    // 2) Send metadata + the FILE to your Node.js server with a Bearer token
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final idToken = await user.getIdToken();
      final displayName = user.displayName ?? user.email ?? user.uid;

      // Build the MultipartRequest
      final uri = Uri.parse(FileService.uploadUrl(widget.groupId));
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $idToken'
        ..fields['uploadedByUid'] = user.uid
        ..fields['uploadedByName'] = displayName
        ..fields['fileUrl'] = downloadUrl;

      // Attach the file under the same key your server expects:
      if (path != null) {
        req.files.add(await http.MultipartFile.fromPath(
          'file',
          path,
          filename: file.name,
        ));
      } else {
        req.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        ));
      }

      // Fire off the request
      final streamedRes = await req.send();
      final body = await streamedRes.stream.bytesToString();
      print('📥 status=${streamedRes.statusCode}, body=$body');

      if (streamedRes.statusCode == 200) {
        setState(() {
          _uploading = false;
          _uploadStatus = "Upload successful!";
        });
      } else {
        setState(() {
          _uploading = false;
          _uploadStatus = "Server error: ${streamedRes.statusCode}";
        });
      }
    } catch (e) {
      print("❌ Server call failed: $e");
      setState(() {
        _uploading = false;
        _uploadStatus = "Upload failed: $e";
      });
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Upload Files"),
        backgroundColor: const Color(0xFF5F0707),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_uploading)
              Column(
                children: [
                  CircularProgressIndicator(value: _uploadProgress),
                  const SizedBox(height: 8),
                  Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ElevatedButton(
              onPressed: _uploading ? null : _pickAndUploadFile,
              child: const Text("Upload File"),
            ),
            if (_uploadStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(_uploadStatus),
              ),
          ],
        ),
      ),
    );
  }
}
