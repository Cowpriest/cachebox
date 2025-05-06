import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart'; // You can swap themes

class TextViewerScreen extends StatelessWidget {
  final String textContent;
  final String fileName;

  const TextViewerScreen({
    required this.textContent,
    required this.fileName,
  });

  String _detectLanguage(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'dart':
        return 'dart';
      case 'py':
        return 'python';
      case 'java':
        return 'java';
      case 'kt':
      case 'kts':
        return 'kotlin';
      case 'c':
      case 'h':
        return 'c';
      case 'cpp':
      case 'cc':
      case 'cxx':
      case 'hpp':
      case 'hxx':
        return 'cpp';
      case 'js':
        return 'javascript';
      case 'ts':
        return 'typescript';
      case 'html':
        return 'xml';
      case 'css':
        return 'css';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'rb':
        return 'ruby';
      case 'go':
        return 'go';
      case 'rs':
        return 'rust';
      case 'php':
        return 'php';
      case 'sql':
        return 'sql';
      case 'sh':
      case 'bash':
        return 'bash';
      case 'xml':
        return 'xml';
      case 'swift':
        return 'swift';
      case 'scala':
        return 'scala';
      case 'lua':
        return 'lua';
      default:
        return 'plaintext';
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = _detectLanguage(fileName);
    return Scaffold(
      appBar: AppBar(title: Text(fileName)),
      body: InteractiveViewer(
        minScale: 0.25,
        maxScale: 5.0,
        constrained: false, // important for zooming out
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            padding: EdgeInsets.all(16),
            child: HighlightView(
              textContent,
              language: language,
              theme: atomOneDarkTheme,
              textStyle: TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
