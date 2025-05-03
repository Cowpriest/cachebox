import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class JoinGroupScreen extends StatefulWidget {
  @override
  _JoinGroupScreenState createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final code = _codeCtrl.text.trim().toUpperCase();

    try {
      final snap = await FirebaseFirestore.instance
          .collection('groups')
          .where('inviteCode', isEqualTo: code)
          .get();

      if (snap.docs.isEmpty) {
        setState(() {
          _error = 'Invalid code';
          _loading = false;
        });
        return;
      }

      final grp = snap.docs.first;

      print("🔥 Sending update to group: ${grp.reference.path}");
      print("🧪 Using arrayUnion to add: $uid");

      // ✅ Safe Firestore-native update
      await grp.reference.update({
        'members': FieldValue.arrayUnion([uid])
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined "${grp['name']}"!')),
      );
      Navigator.pop(context);
    } catch (e) {
      print("❌ Firestore update failed: $e");
      setState(() {
        _error = 'Failed to join group: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Join Group')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _codeCtrl,
              decoration: InputDecoration(labelText: 'Invite Code'),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Colors.red)),
            ],
            SizedBox(height: 20),
            _loading
                ? CircularProgressIndicator()
                : ElevatedButton(onPressed: _join, child: Text('Join')),
          ],
        ),
      ),
    );
  }
}
