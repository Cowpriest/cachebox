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
    //debugGroupQuery();
  }

  // Future<void> debugGroupQuery() async {
  //   final uid = FirebaseAuth.instance.currentUser!.uid;
  //   final ref = FirebaseFirestore.instance.collection('groups');

  //   print('🚧 DEBUG: about to run query:'
  //       ' .where("members", arrayContains: $uid)'
  //       ' .orderBy(FieldPath.documentId)'
  //       ' .limit(1)');

  //   try {
  //     final snap = await ref
  //         .where('members', arrayContains: uid)
  //         .orderBy(FieldPath.documentId)
  //         .limit(1)
  //         .get();
  //     print('✅ DEBUG: query succeeded, docs returned=${snap.docs.length}');
  //   } on FirebaseException catch (e) {
  //     print('❌ DEBUG: FirebaseException.code = ${e.code}');
  //     print('❌ DEBUG: FirebaseException.message = ${e.message}');
  //   } catch (e) {
  //     print('❌ DEBUG: unknown error: $e');
  //   }
  // }

  Future<void> _leaveGroup(String groupId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .update({
        'members': FieldValue.arrayRemove([uid]),
        'admins': FieldValue.arrayRemove([uid]),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left the group.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error leaving group: $e')),
      );
    }
  }

  Future<void> _signOut(BuildContext ctx) async {
    // clear any group-deletion banners before we zap auth
    ScaffoldMessenger.of(ctx).clearMaterialBanners();
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
        title: const Text('Your Groups'),
        actions: [
          TextButton(
            onPressed: () => _signOut(ctx),
            child: Text('Logout'),
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
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 1) grab all docs
          final docs = snapshot.data?.docs ?? [];
          final now = DateTime.now();

          // 2) filter out any group whose deletionTimestamp is past
          final visible = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = data['deletionTimestamp'] as Timestamp?;
            return ts == null || ts.toDate().isAfter(now);
          }).toList();

          if (visible.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '😴 You’re not in any groups yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.group_add),
                      label: const Text('Create a Group'),
                      onPressed: () => Navigator.push(
                        ctx,
                        MaterialPageRoute(builder: (_) => CreateGroupScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      child: const Text('Join a Group by Code'),
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

          return ListView(
            children: [
              ...visible.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = data['name'] as String;
                final ownerUid = data['ownerUid'] as String?;
                final adminUids = (data['adminUids'] as List?)
                    ?.map((e) => e as String)
                    .toList();

                // Pending _future_ deletion?
                final ts = data['deletionTimestamp'] as Timestamp?;
                final isPending = ts != null && ts.toDate().isAfter(now);

                return ListTile(
                  leading: isPending
                      ? const Icon(Icons.warning_rounded,
                          color: Colors.orangeAccent)
                      : null,
                  title: Text(name),
                  subtitle: isPending
                      ? const Text(
                          'Pending deletion',
                          style: TextStyle(color: Colors.orangeAccent),
                        )
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupHomeScreen(
                        groupId: doc.id,
                        groupName: name,
                        ownerUid: ownerUid,
                        adminUids: adminUids,
                      ),
                    ),
                  ),
                  trailing: uid == ownerUid
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            'Owner',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        )
                      : PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (choice) {
                            if (choice == 'leave') _leaveGroup(doc.id);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'leave', child: Text('Leave group')),
                          ],
                        ),
                );
              }),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.group_add),
                title: const Text('Create New Group'),
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => CreateGroupScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Join Group by Code'),
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
