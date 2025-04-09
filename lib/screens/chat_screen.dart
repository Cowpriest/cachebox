// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:cachebox/screens/login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
        title: Text('CacheBox | ${FirebaseAuth.instance.currentUser?.email}'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance
                  .signOut(); // this is old method, remove once google sign-in works
              await GoogleSignIn().signOut();
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
                    final isMe = data['displayName'] ==
                        FirebaseAuth.instance.currentUser?.displayName;

                    // Format the timestamp if available
                    String formattedTimestamp = '';
                    if (data['timestamp'] != null) {
                      DateTime timestamp =
                          (data['timestamp'] as Timestamp).toDate();
                      String formattedTime =
                          DateFormat('hh:mm a').format(timestamp);
                      String formattedDate =
                          DateFormat('MM-dd-yy').format(timestamp);
                      formattedTimestamp = '$formattedTime $formattedDate';
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          // Wrap the bubble in a Stack so we can overlay the display name
                          Stack(
                            clipBehavior: Clip
                                .none, // allows the Positioned widget to overflow
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 2 / 3,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? const Color.fromARGB(255, 52, 52, 52)
                                        : const Color.fromARGB(
                                            255, 16, 90, 201),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(12),
                                      topRight: const Radius.circular(12),
                                      bottomLeft: isMe
                                          ? const Radius.circular(12)
                                          : const Radius.circular(0),
                                      bottomRight: isMe
                                          ? const Radius.circular(0)
                                          : const Radius.circular(12),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // The main message text
                                      Text(
                                        data['text'] ?? '',
                                        style: TextStyle(
                                          color: Colors.white,
                                          shadows: [
                                            Shadow(
                                                offset: Offset(-1, -1),
                                                blurRadius: 2,
                                                color: Colors.black),
                                            Shadow(
                                                offset: Offset(1, -1),
                                                blurRadius: 2,
                                                color: Colors.black),
                                            Shadow(
                                                offset: Offset(1, 1),
                                                blurRadius: 2,
                                                color: Colors.black),
                                            Shadow(
                                                offset: Offset(-1, 1),
                                                blurRadius: 2,
                                                color: Colors.black),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      // Timestamp at the bottom-right
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            formattedTimestamp,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: const Color.fromARGB(
                                                  118, 0, 0, 0),
                                              shadows: [
                                                Shadow(
                                                    offset: Offset(0.6, 0.6),
                                                    blurRadius: 1,
                                                    color: Colors.black),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Overlay the display name for non-logged-in messages
                              if (!isMe)
                                Positioned(
                                  top:
                                      -12, // Adjust this value to control vertical overlap
                                  left:
                                      0, // Adjust this value to control horizontal position
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    color: Colors.transparent,
                                    child: Text(
                                      data['displayName'] ?? '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.white,
                                        shadows: [
                                          Shadow(
                                              offset: Offset(-1, -1),
                                              blurRadius: 2,
                                              color: Colors.black),
                                          Shadow(
                                              offset: Offset(1, -1),
                                              blurRadius: 2,
                                              color: Colors.black),
                                          Shadow(
                                              offset: Offset(1, 1),
                                              blurRadius: 2,
                                              color: Colors.black),
                                          Shadow(
                                              offset: Offset(-1, 1),
                                              blurRadius: 2,
                                              color: Colors.black),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
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
