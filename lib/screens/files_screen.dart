// lib/screens/files_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../services/file_service.dart';
import '../services/file_model.dart';
import 'video_player_screen.dart';
import 'audio_player_screen.dart';
import 'image_viewer_screen.dart';
import 'text_viewer_screen.dart';

class FilesScreen extends StatefulWidget {
  final String groupId;
  final String ownerUid;
  final List<String> adminUids;

  const FilesScreen({
    required this.groupId,
    required this.ownerUid,
    required this.adminUids,
    Key? key,
  }) : super(key: key);

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
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
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  void _hideLoadingDialog() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    final groupId = widget.groupId;
    print('🔄 FilesScreen._refresh for groupId=$groupId');
    try {
      final fetched = await FileService.listFiles(widget.groupId);
      print('✅ _refresh succeeded, loaded ${files.length} files');
      setState(() => files = fetched);
    } catch (e, st) {
      // print to console for full stack
      debugPrint('❌ listFiles error: $e\n$st');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Failed to fetch files:\n$e')));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _upload() async {
    _showLoadingDialog();
    try {
      await FileService.uploadFile(widget.groupId);
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
      if (['.mp4', '.webm'].contains(ext)) {
        _hideLoadingDialog();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VideoPlayerScreen(videoUrl: url)),
        );
      } else if (['.mp3', '.wav'].contains(ext)) {
        _hideLoadingDialog();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AudioPlayerScreen(audioUrl: url)),
        );
      } else if (['.jpg', '.jpeg', '.png', '.gif'].contains(ext)) {
        _hideLoadingDialog();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ImageViewerScreen(imageUrl: url)),
        );
      } else if (['.pdf'].contains(ext)) {
        _hideLoadingDialog();
        // download to temp, then...
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Failed to download PDF (${response.statusCode})');
        }
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = '${tmpDir.path}/${file.fileName}';
        await File(tmpPath).writeAsBytes(response.bodyBytes, flush: true);

        // then navigate to our new PdfViewerScreen:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              filePath: tmpPath,
              fileName: file.fileName,
            ),
          ),
        );
      } else {
        // treat everything else as text/code
        final response = await http.get(Uri.parse(url));
        _hideLoadingDialog();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TextViewerScreen(
              textContent: utf8.decode(response.bodyBytes),
              fileName: file.fileName,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('❌ Failed to load file')));
      _hideLoadingDialog();
    }
  }

  Future<void> _delete(FileModel file) async {
    _showLoadingDialog();
    try {
      await FileService.deleteFile(widget.groupId, file);
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
        title: const Text('Group Files'),
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
                  final currentUid = FirebaseAuth.instance.currentUser!.uid;
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
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.red,
                            ),
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

/// A standalone screen that opens a local PDF file with pinch‐to‐zoom and scrolling,
/// and disposes of its controller properly.
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
    // Create a controller that will load the PDF and allow pinch/zoom + scroll
    _pdfController = PdfControllerPinch(
      document: PdfDocument.openFile(widget.filePath),
      initialPage: 1,
    );
  }

  @override
  void dispose() {
    // Dispose of the controller (which closes the document under the hood)
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.fileName)),
      body: PdfViewPinch(
        controller: _pdfController,
        onPageChanged: (page) => debugPrint('📄 Page changed to $page'),
        // you can tweak these if you want:
        // enableDoubleTap: true,
        // minScale: 1.0,
        // maxScale: 3.0,
      ),
    );
  }
}
