import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'file_upload_screen.dart'; // Import your file upload screen
import 'package:url_launcher/url_launcher.dart';

void _launchURL(String url) async {
  Uri uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    print("❌ Could not launch URL: $url");
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

              return ListTile(
                title: Text(data['fileName'] ?? 'Unnamed file'),
                subtitle: Text(data['uploadedAt'] != null
                    ? (data['uploadedAt'] as Timestamp).toDate().toString()
                    : 'No date'),
                trailing: IconButton(
                  icon: Icon(Icons.download),
                  onPressed: () {
                    if (data['fileUrl'] != null) {
                      print("🔗 Opening URL: ${data['fileUrl']}");
                      _launchURL(data['fileUrl']);
                    } else {
                      print("❌ No file URL found for ${data['fileName']}");
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    ); // ✅ Only one closing parenthesis here
  }
}
