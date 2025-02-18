// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:cachebox/screens/login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final CollectionReference _messages =
      FirebaseFirestore.instance.collection('messages');

  void sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    // Get the current user's display name (or use a default value)
    final displayName =
        FirebaseAuth.instance.currentUser?.displayName ?? 'Anonymous';
    _messages.add({
      'text': _messageController.text.trim(),
      'displayName': displayName,
      'timestamp': FieldValue.serverTimestamp(),
      // Optionally add user info here (e.g., uid, displayName)
    });
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // Removes the default back button
        title: Text('CacheBox'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  _messages.orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    // Display the message text along with the user's display name.
                    return ListTile(
                      title: Text(data['displayName'] ?? 'Anonymous'),
                      subtitle: Text(data['text'] ?? ''),
                      trailing: data['timestamp'] != null
                          ? Text(data['timestamp']
                              .toDate()
                              .toLocal()
                              .toString()
                              .substring(0, 16))
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Enter your message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
