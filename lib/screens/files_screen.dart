// lib/screens/files_screen.dart
import 'package:flutter/material.dart';
import 'package:cachebox/services/jellyfin_service.dart'; // Import the service
import 'package:cachebox/screens/video_player_screen.dart';
import 'package:cachebox/screens/audio_streaming_screen.dart';
import 'package:cachebox/screens/pdf_from_network_page.dart';
import 'package:cachebox/screens/file_viewer_screen.dart'; // For fallback viewing
import 'package:flutter_slidable/flutter_slidable.dart';

class FilesScreen extends StatefulWidget {
  final String? parentId;

  const FilesScreen({Key? key, this.parentId}) : super(key: key);

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late Future<List<JellyfinItem>> _futureItems;

  @override
  void initState() {
    super.initState();
    _futureItems = JellyfinService().fetchItems(parentId: widget.parentId);
  }

void _openItem(JellyfinItem item) {
  if (item.isFolder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FilesScreen(parentId: item.id),
      ),
    );
  } else {
    print('🎬 Tapped on movie: ${item.name} (ID: ${item.id})');
    final streamUrl = JellyfinService().getStreamUrl(item.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          streamUrl: streamUrl,
          title: item.name,
        ),
      ),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Media'),
        backgroundColor: const Color(0xFF5F0707),
        automaticallyImplyLeading: false, // 🚫 No back button
      ),
      body: FutureBuilder<List<JellyfinItem>>(
        future: _futureItems,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
                child: Text('Failed to load files: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No shared media found.'));
          } else {
            final items = snapshot.data!;
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Icon(
                    item.isFolder ? Icons.folder : Icons.movie,
                    color: item.isFolder ? Colors.amber : Colors.blueAccent,
                  ),
                  title: Text(item.name),
                  subtitle: Text(item.type),
                  trailing: TextButton(
                    child: Text(item.isFolder ? 'Open' : 'View'),
                    onPressed: () {
                      _openItem(item);
                    },
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
