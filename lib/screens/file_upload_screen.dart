// lib/screens/file_upload_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FileUploadScreen extends StatefulWidget {
  const FileUploadScreen({Key? key}) : super(key: key);

  @override
  _FileUploadScreenState createState() => _FileUploadScreenState();
}

class _FileUploadScreenState extends State<FileUploadScreen> {
  bool _uploading = false;
  String? _uploadStatus;
  double _uploadProgress = 0.0;

Future<void> _pickAndUploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _uploading = true;
        _uploadStatus = "Uploading...";
        _uploadProgress = 0.0; // Reset progress
      });

      final file = result.files.single;
      String? filePath = file.path; // Path for physical devices
      Uint8List? fileBytes = file.bytes; // Bytes for web

      print("🟢 File Selected: ${file.name}");
      print("📂 File Path: ${filePath ?? 'No file path available'}");
      print("📏 File Size: ${file.size} bytes");

      // If fileBytes is null, try reading from file path (for physical devices)
      if (fileBytes == null) {
        if (filePath != null) {
          try {
            print("🔍 Attempting to read bytes from file path...");
            fileBytes = await File(filePath).readAsBytes();
            print("✅ File bytes successfully read (${fileBytes.length} bytes)");
          } catch (e) {
            print("❌ Error reading file bytes: $e");
            setState(() {
              _uploadStatus = "Error reading file.";
              _uploading = false;
            });
            return;
          }
        } else {
          print("❌ File path is null. Cannot read file bytes.");
          setState(() {
            _uploadStatus = "File path is null.";
            _uploading = false;
          });
          return;
        }
      }

      // Set Firebase Storage reference
      final storageRef =
          FirebaseStorage.instance.ref().child('shared_files/${file.name}');
      print("🚀 Attempting to upload to: ${storageRef.fullPath}");

      try {
        final UploadTask uploadTask = storageRef.putData(fileBytes);

        // Listen to snapshot events and update _uploadProgress.
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          double progress = snapshot.bytesTransferred / snapshot.totalBytes;
          print('📈 Upload progress: ${(progress * 100).toStringAsFixed(0)}%');
          setState(() {
            _uploadProgress = progress;
          });
        });

        // Wait for the upload to complete
        await uploadTask;

        // Once the file is uploaded, retrieve its download URL
        final downloadUrl = await storageRef.getDownloadURL();
        print('🔗 Download URL: $downloadUrl');

        // Save metadata to Firestore
        await FirebaseFirestore.instance.collection('shared_files').add({
          'fileName': file.name,
          'fileUrl': downloadUrl,
          'uploadedAt': FieldValue.serverTimestamp(),
          'uploadedBy': FirebaseAuth.instance.currentUser?.email ?? "Unknown",
          'fileSize': file.size,
        });

        print("✅ File metadata saved to Firestore: ${file.name}");

        setState(() {
          _uploadStatus = "Upload successful!";
          _uploading = false;
        });
      } catch (e) {
        print("❌ Upload failed: $e");
        setState(() {
          _uploadStatus = "Upload failed: $e";
          _uploading = false;
        });
      }
    } else {
      print("⚠ No file selected.");
    }
  }


  @override
  Widget build(BuildContext context) {
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
                  CircularProgressIndicator(
                    value: _uploadProgress,
                  ),
                  SizedBox(height: 8),
                  Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ElevatedButton(
              onPressed: _uploading ? null : _pickAndUploadFile,
              child: const Text("Upload File"),
            ),
            if (_uploadStatus != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(_uploadStatus!),
              ),
          ],
        ),
      ),
    );
  }
}
