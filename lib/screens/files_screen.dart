// lib/screens/files_screen.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../services/file_service.dart';
import '../services/file_model.dart';
import 'video_player_screen.dart';
import 'audio_player_screen.dart';
import 'image_viewer_screen.dart';
import 'text_viewer_screen.dart';

class FilesScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String ownerUid;
  final List<String> adminUids;

  const FilesScreen({
    required this.groupId,
    required this.groupName,
    required this.ownerUid,
    required this.adminUids,
    Key? key,
  }) : super(key: key);

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _service = FileService();
  List<FileModel> files = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _hideLoadingDialog() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final fetched = await _service.listFiles(widget.groupId, sync: true);
      setState(() => files = fetched);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch files: $e')),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _upload() async {
    // Let the user pick any file
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) {
      return; // user cancelled
    }
    final path = result.files.single.path!;
    final name = result.files.single.name;

    _showLoadingDialog();
    try {
      // fieldName is 'file' to match your multer setup
      await _service.uploadFile(
        widget.groupId,
        filePath: path, // or fileBytes: picked.bytes
        filename: name,
      );
      await _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Upload failed: $e')),
      );
    } finally {
      _hideLoadingDialog();
    }
  }

  Future<void> _openFile(FileModel file) async {
    _showLoadingDialog();
    final url = file.fileUrl;
    final ext = p.extension(file.fileName).toLowerCase();

    try {
      if (['.mp4', '.webm', '.mkv'].contains(ext)) {
        _hideLoadingDialog();
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(videoUrl: url),
            ));
      } else if (['.mp3', '.wav'].contains(ext)) {
        _hideLoadingDialog();
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AudioPlayerScreen(audioUrl: url),
            ));
      } else if (['.jpg', '.jpeg', '.png', '.gif'].contains(ext)) {
        _hideLoadingDialog();
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ImageViewerScreen(imageUrl: url),
            ));
      } else if (ext == '.pdf') {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Failed to download PDF (${response.statusCode})');
        }
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = '${tmpDir.path}/${file.fileName}';
        await File(tmpPath).writeAsBytes(response.bodyBytes, flush: true);

        _hideLoadingDialog();
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PdfViewerScreen(
                filePath: tmpPath,
                fileName: file.fileName,
              ),
            ));
      } else {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Failed to download file (${response.statusCode})');
        }
        final text = utf8.decode(response.bodyBytes);
        _hideLoadingDialog();
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TextViewerScreen(
                textContent: text,
                fileName: file.fileName,
              ),
            ));
      }
    } catch (e) {
      _hideLoadingDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to open file: $e')),
      );
    }
  }

  Future<void> _delete(FileModel file) async {
    _showLoadingDialog();
    try {
      await _service.deleteFile(widget.groupId, file.id);
      await _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Delete failed: $e')),
      );
    } finally {
      _hideLoadingDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(widget.groupName),
        actions: [
          IconButton(onPressed: _upload, icon: const Icon(Icons.upload_file)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                itemCount: files.length,
                itemBuilder: (_, i) {
                  final file = files[i];
                  final canDelete = currentUid == file.uploadedByUid ||
                      currentUid == widget.ownerUid ||
                      widget.adminUids.contains(currentUid);
                  return ListTile(
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text(file.fileName),
                    subtitle: Text('by ${file.uploadedByName}'),
                    onTap: () => _openFile(file),
                    trailing: canDelete
                        ? IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _delete(file),
                          )
                        : null,
                  );
                },
              ),
            ),
    );
  }
}

/// In‐app PDF viewer with pinch‐zoom & scroll
class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;
  const PdfViewerScreen({
    required this.filePath,
    required this.fileName,
    Key? key,
  }) : super(key: key);

  @override
  _PdfViewerScreenState createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfControllerPinch _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfControllerPinch(
      document: PdfDocument.openFile(widget.filePath),
      initialPage: 1,
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.fileName)),
      body: PdfViewPinch(
        controller: _pdfController,
        onPageChanged: (page) => debugPrint('📄 Page $page'),
      ),
    );
  }
}
