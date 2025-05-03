import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // ← for Clipboard
import 'chat_screen.dart';
import 'files_screen.dart';

class GroupHomeScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupHomeScreen({required this.groupId, required this.groupName});

  @override
  _GroupHomeScreenState createState() => _GroupHomeScreenState();
}

class _GroupHomeScreenState extends State<GroupHomeScreen> {
  String? _inviteCode;
  String? _createdBy;
  bool _loadingCode = true;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _fetchGroupInfo();
  }

  Future<void> _fetchGroupInfo() async {
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .get();
    setState(() {
      _inviteCode = doc['inviteCode'] as String?;
      _createdBy = doc['createdBy'] as String?;
      _loadingCode = false;
    });
  }

  void _showInviteCode() {
    if (_inviteCode == null) return;
    // copy to clipboard
    Clipboard.setData(ClipboardData(text: _inviteCode!));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Invite Code'),
        content: SelectableText(_inviteCode!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ChatScreen(groupId: widget.groupId),
      FilesScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          if (!_loadingCode &&
              _createdBy == FirebaseAuth.instance.currentUser!.uid)
            IconButton(
              icon: Icon(Icons.vpn_key),
              tooltip: 'Show Invite Code',
              onPressed: _showInviteCode,
            ),
        ],
      ),
      body: screens[_selected],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selected,
        onTap: (i) => setState(() => _selected = i),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Files'),
        ],
      ),
    );
  }
}
