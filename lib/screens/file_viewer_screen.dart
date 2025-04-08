// lib/screens/file_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:cachebox/screens/video_streaming_screen.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

class FileViewerScreen extends StatefulWidget {
  final String fileUrl;
  final String fileName;
  const FileViewerScreen({Key? key, required this.fileUrl, required this.fileName})
      : super(key: key);

  @override
  _FileViewerScreenState createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  Future<String>? _textContentFuture;
  Future<Uint8List>? _pdfBytesFuture;

  @override
  void initState() {
    super.initState();
    final lowerName = widget.fileName.toLowerCase();

    // Initialize a future for text or PDF files
    if (lowerName.endsWith('.txt') || lowerName.endsWith('.code')) {
      _textContentFuture = _fetchText(widget.fileUrl);
    } else if (lowerName.endsWith('.pdf')) {
      _pdfBytesFuture = _fetchPdfBytes(widget.fileUrl);
    }
  }

  /// Fetch text content from the remote URL.
  Future<String> _fetchText(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to load text file');
    }
  }

  /// Fetch PDF bytes from the remote URL.
  Future<Uint8List> _fetchPdfBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to load PDF file');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowerName = widget.fileName.toLowerCase();

    // Video file: use your VideoStreamingScreen
    if (lowerName.endsWith('.mp4')) {
      return VideoStreamingScreen(videoUrl: widget.fileUrl);

      // Image file: display with Image.network
    } else if (lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.gif')) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.fileName)),
        body: Center(child: Image.network(widget.fileUrl)),
      );

      // PDF file: use pdfx to display the PDF from remote bytes
    } else if (lowerName.endsWith('.pdf')) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.fileName)),
        body: FutureBuilder<Uint8List>(
          future: _pdfBytesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text("Error loading PDF: ${snapshot.error}"));
            } else if (snapshot.hasData) {
              final pdfPinchController = PdfControllerPinch(
                document: PdfDocument.openData(
                  snapshot.data!,                  
                ),
              );
              return PdfViewPinch(controller: pdfPinchController);
            }
            return const Center(child: Text("No PDF data found."));
          },
        ),
      );

      // Text or code file: fetch and display as text.
    } else if (lowerName.endsWith('.txt') || lowerName.endsWith('.code')) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.fileName)),
        body: FutureBuilder<String>(
          future: _textContentFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text("Error loading file: ${snapshot.error}"));
            } else if (snapshot.hasData) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(
                  snapshot.data!,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              );
            }
            return const Center(child: Text("No text data found."));
          },
        ),
      );
    } else {
      // Fallback for unsupported file types.
      return Scaffold(
        appBar: AppBar(title: Text(widget.fileName)),
        body: const Center(child: Text("Unsupported file type.")),
      );
    }
  }
}
