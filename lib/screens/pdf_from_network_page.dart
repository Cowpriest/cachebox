// lib/screens/pdf_from_network_page.dart
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

class PdfFromNetworkPage extends StatefulWidget {
  final String pdfUrl;
  final String fileName; // For display in the AppBar
  const PdfFromNetworkPage(
      {Key? key, required this.pdfUrl, required this.fileName})
      : super(key: key);

  @override
  _PdfFromNetworkPageState createState() => _PdfFromNetworkPageState();
}

class _PdfFromNetworkPageState extends State<PdfFromNetworkPage> {
  Future<Uint8List>? _pdfBytes;

  @override
  void initState() {
    super.initState();
    _pdfBytes = _fetchPdfBytes(widget.pdfUrl);
  }

  /// Fetches PDF bytes from the remote URL using the http package.
  Future<Uint8List> _fetchPdfBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception("Failed to load PDF from network");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
      ),
      body: FutureBuilder<Uint8List>(
        future: _pdfBytes,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Error loading PDF: ${snapshot.error}"));
          }
          if (snapshot.hasData) {
            // Once we have the bytes, create the PdfControllerPinch
            final PdfControllerPinch pdfController = PdfControllerPinch(
              document: PdfDocument.openData(
                snapshot.data!,
              ),
            );
            return PdfViewPinch(
              controller: pdfController,
            );
          }
          return const Center(child: Text("No PDF data found."));
        },
      ),
    );
  }
}
