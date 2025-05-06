// lib/screens/group_list_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_screen.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';
import 'group_home_screen.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({Key? key}) : super(key: key);

  @override
  _GroupListScreenState createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  @override
  void initState() {
    super.initState();
    debugGroupQuery();

    FirebaseFirestore.instance
        .collection('__debug')
        .doc('ping')
        .set({'ts': FieldValue.serverTimestamp()})
        .then((_) => print('🔄 PING succeeded'))
        .catchError((e) => print('⚠️ PING failed: $e'));
  }

  /// Prints exactly what Firestore sees, and logs any permission error
  Future<void> debugGroupQuery() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance.collection('groups');

    print('🚧 DEBUG: about to run query:'
        ' .where("members", arrayContains: $uid)'
        ' .orderBy(FieldPath.documentId)'
        ' .limit(1)');

    try {
      final snap = await ref
          .where('members', arrayContains: uid)
          .orderBy(FieldPath.documentId)
          .limit(1)
          .get();
      print('✅ DEBUG: query succeeded, docs returned=${snap.docs.length}');
    } on FirebaseException catch (e) {
      print('❌ DEBUG: FirebaseException.code = ${e.code}');
      print('❌ DEBUG: FirebaseException.message = ${e.message}');
    } catch (e) {
      print('❌ DEBUG: unknown error: $e');
    }
  }

  Future<void> _signOut(BuildContext ctx) async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();
    Navigator.pushReplacement(
      ctx,
      MaterialPageRoute(builder: (_) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Your Groups'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _signOut(ctx),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('groups')
            .where('members', arrayContains: uid)
            .orderBy(FieldPath.documentId)
            .snapshots(),
        builder: (ctx, snapshot) {
          // 1. Error state
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          // 2. Loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          // 3. Data state
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            // Empty-state UI
            return Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '😴 You’re not in any groups yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: Icon(Icons.group_add),
                      label: Text('Create a Group'),
                      onPressed: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(builder: (_) => CreateGroupScreen()),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextButton(
                      child: Text('Join a Group by Code'),
                      onPressed: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(builder: (_) => JoinGroupScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          // 4. Normal list + buttons
          return ListView(
            children: [
              ...docs.map((doc) {
                final name = doc['name'] as String;
                return ListTile(
                  title: Text(name),
                  onTap: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => GroupHomeScreen(
                        groupId: doc.id,
                        groupName: name,
                      ),
                    ),
                  ),
                );
              }),
              Divider(),
              ListTile(
                leading: Icon(Icons.group_add),
                title: Text('Create New Group'),
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => CreateGroupScreen()),
                ),
              ),
              ListTile(
                leading: Icon(Icons.login),
                title: Text('Join Group by Code'),
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => JoinGroupScreen()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
