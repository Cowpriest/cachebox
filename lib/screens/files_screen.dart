import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'file_upload_screen.dart'; // Import your file upload screen
import 'package:url_launcher/url_launcher.dart';
import 'package:cachebox/screens/video_streaming_screen.dart';
import 'package:cachebox/screens/file_viewer_screen.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

void _launchURL(String url) async {
  Uri uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    print("❌ Could not launch URL: $url");
  }
}

Future<void> deleteFile(String docId, String fileName) async {
  try {
    // Reference the file in Firebase Storage.
    final storageRef =
        FirebaseStorage.instance.ref().child('shared_files/$fileName');
    await storageRef.delete(); // Delete the file from Storage.

    // Now delete the metadata from Firestore.
    await FirebaseFirestore.instance
        .collection('shared_files')
        .doc(docId)
        .delete();

    print('File and metadata deleted successfully.');
  } catch (e) {
    print('Error deleting file: $e');
  }
}


class FilesScreen extends StatelessWidget {
  const FilesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Files'),
        backgroundColor: const Color(0xFF5F0707),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: () {
              // Navigate to the file upload screen when pressed
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FileUploadScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection(
                'shared_files') // Ensure this collection name matches Firebase
            .orderBy('uploadedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          print("🔍 Checking Firestore snapshot for files...");

          if (snapshot.hasError) {
            print("❌ Firestore Error: ${snapshot.error}");
            return Center(child: Text("Error loading files"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            print("⏳ Firestore is still loading...");
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            print("📭 No files found in Firestore!");
            return Center(child: Text("No files uploaded yet."));
          }

          print("✅ Files loaded successfully!");
          final docs = snapshot.data!.docs;

return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              print(
                  "📂 File: ${data['fileName']} uploaded by ${data['uploadedBy']}");
    
              return Slidable(
                key: Key(docs[index].id),
                // Define the action pane that appears from the right side
                endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio:
                      0.25, // Adjust this to control how much of the tile is revealed
                  children: [
                    SlidableAction(
                      onPressed: (context) async {
                        // Call your delete function here. Make sure deleteFile is defined.
                        await deleteFile(docs[index].id, data['fileName']);
                      },
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      icon: Icons.delete,
                      label: 'Delete',
                    ),
                  ],
                ),
                // The main tile displays your file metadata and a "View" button
                child: ListTile(
                  title: Text(data['fileName'] ?? 'Unnamed file'),
                  subtitle: Text(
                    data['uploadedAt'] != null
                        ? (data['uploadedAt'] as Timestamp).toDate().toString()
                        : 'No date',
                  ),
                  trailing: TextButton(
                    child: const Text("View"),
                    onPressed: () {
                      if (data['fileUrl'] != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FileViewerScreen(
                              fileUrl: data['fileUrl'],
                              fileName: data['fileName'],
                            ),
                          ),
                        );
                      } else {
                        print("❌ No file URL found for ${data['fileName']}");
                      }
                    },
                  ),

                ),
              );
            },
          );

        },
      ),
    ); // ✅ Only one closing parenthesis here
  }
}
