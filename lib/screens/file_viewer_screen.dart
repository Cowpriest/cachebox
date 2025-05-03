import 'package:flutter/material.dart';
import 'package:cachebox/screens/video_player_screen.dart'; // ✅ Import the correct player screen
import 'package:cachebox/services/jellyfin_service.dart';   // ✅ Import Jellyfin service

class FileViewerScreen extends StatelessWidget {
  final String fileId;   // ✅ We now expect the file's **ItemId**, not raw URL or filename
  final String fileName; // ✅ So we can show title

  const FileViewerScreen({Key? key, required this.fileId, required this.fileName})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        backgroundColor: const Color(0xFF5F0707),
      ),
      body: Center(
        child: ElevatedButton(
          child: const Text('Play Video'),
          onPressed: () {
            final streamUrl = JellyfinService().getStreamUrl(fileId);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(
                  streamUrl: streamUrl,
                  title: fileName,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
