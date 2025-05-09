import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // for Clipboard
import 'dart:math';

class CreateGroupScreen extends StatefulWidget {
  @override
  _CreateGroupScreenState createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  bool _loading = false;

  String _makeCode(int len) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(
        len,
        (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
      ),
    );
  }

  Future<void> _create() async {
    setState(() => _loading = true);
    final code = _makeCode(6);
    Clipboard.setData(ClipboardData(text: code!));
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('groups').add({
      'name': _nameCtrl.text.trim(),
      'inviteCode': code,
      'ownerUid': uid,
      'members': [uid],
      'admins': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() => _loading = false);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Group Created'),
        content: Text('Invite Code: $code'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create Group')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: 'Group Name'),
            ),
            SizedBox(height: 20),
            _loading
                ? CircularProgressIndicator()
                : ElevatedButton(onPressed: _create, child: Text('Create')),
          ],
        ),
      ),
    );
  }
}
