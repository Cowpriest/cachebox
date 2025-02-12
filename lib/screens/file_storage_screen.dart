// lib/screens/file_storage_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

class FileStorageScreen extends StatefulWidget {
  @override
  _FileStorageScreenState createState() => _FileStorageScreenState();
}

class _FileStorageScreenState extends State<FileStorageScreen> {
  final FirebaseStorage storage = FirebaseStorage.instance;
  String? uploadStatus;

  Future<void> pickAndUploadFile() async {
    // Pick a file
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    // Get file details
    final fileBytes = result.files.first.bytes;
    final fileName = result.files.first.name;

    if (fileBytes != null) {
      // Upload file
      try {
        await storage.ref('shared_files/$fileName').putData(fileBytes);
        setState(() {
          uploadStatus = 'Upload successful!';
        });
      } catch (e) {
        setState(() {
          uploadStatus = 'Upload failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Shared Storage')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: pickAndUploadFile,
              child: Text('Upload File'),
            ),
            if (uploadStatus != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(uploadStatus!),
              ),
          ],
        ),
      ),
    );
  }
}
