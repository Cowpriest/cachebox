// lib/screens/files_screen.dart
import 'package:flutter/material.dart';
import 'package:cachebox/services/jellyfin_service.dart'; // Import the service
import 'package:cachebox/screens/video_streaming_screen.dart';
import 'package:cachebox/screens/audio_streaming_screen.dart';
import 'package:cachebox/screens/pdf_from_network_page.dart';
import 'package:cachebox/screens/file_viewer_screen.dart'; // For fallback viewing
import 'package:flutter_slidable/flutter_slidable.dart';

class FilesScreen extends StatefulWidget {
  final String groupId; // still passed but unused for Jellyfin listing
  const FilesScreen({Key? key, required this.groupId}) : super(key: key);

  @override
  _FilesScreenState createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late Future<List<JellyfinItem>> _futureItems;

  @override
  void initState() {
    super.initState();
    _futureItems = JellyfinService().fetchItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Media'),
        backgroundColor: const Color(0xFF5F0707),
      ),
      body: FutureBuilder<List<JellyfinItem>>(
        future: _futureItems,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            print("❌ Jellyfin error: ${snapshot.error}");
            return Center(child: Text('Error loading media'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No media available.'));
          }

          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];

              return Slidable(
                key: Key(item.id),
                endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.25,
                  children: [
                    SlidableAction(
                      onPressed: (_) {
                        // TODO: Hook up a "Delete from Jellyfin" API if you want
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Delete not yet implemented')),
                        );
                      },
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      icon: Icons.delete,
                      label: 'Delete',
                    ),
                  ],
                ),
                child: ListTile(
                  title: Text(item.name),
                  subtitle: Text(item.mediaType),
                  trailing: TextButton(
                    child: const Text("View"),
                    onPressed: () {
                      _openItem(item);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openItem(JellyfinItem item) {
    final service = JellyfinService();
    final lowerName = item.name.toLowerCase();

    if (lowerName.endsWith('.mp4') || lowerName.endsWith('.mkv')) {
      // Video
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoStreamingScreen(
            videoUrl: service.getStreamUrl(item),
          ),
        ),
      );
    } else if (lowerName.endsWith('.mp3') || lowerName.endsWith('.flac')) {
      // Audio
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudioStreamingScreen(
            audioUrl: service.getStreamUrl(item),
          ),
        ),
      );
    } else if (lowerName.endsWith('.pdf')) {
      // PDF
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfFromNetworkPage(
            pdfUrl: service.getFileUrl(item),
            fileName: item.name,
          ),
        ),
      );
    } else if (lowerName.endsWith('.jpg') || lowerName.endsWith('.png') || lowerName.endsWith('.jpeg')) {
      // Images
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileViewerScreen(
            fileUrl: service.getFileUrl(item),
            fileName: item.name,
          ),
        ),
      );
    } else if (lowerName.endsWith('.txt') || lowerName.endsWith('.code')) {
      // Text/code files
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileViewerScreen(
            fileUrl: service.getFileUrl(item),
            fileName: item.name,
          ),
        ),
      );
    } else {
      // Unknown type fallback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unsupported file type: ${item.mediaType}')),
      );
    }
  }
}
