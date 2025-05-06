// lib/screens/group_home_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // for Clipboard
import 'chat_screen.dart';
import 'files_screen.dart';

class GroupHomeScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupHomeScreen({
    required this.groupId,
    required this.groupName,
    Key? key,
  }) : super(key: key);

  @override
  _GroupHomeScreenState createState() => _GroupHomeScreenState();
}

class _GroupHomeScreenState extends State<GroupHomeScreen> {
  String? _inviteCode;
  String? _ownerUid;
  List<String> _admins = [];
  bool _loadingInfo = true;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _fetchGroupInfo();
  }

  Future<void> _fetchGroupInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
      final data = doc.data();
      if (data != null) {
        setState(() {
          _inviteCode   = data['inviteCode']  as String?;
          _ownerUid     = data['ownerUid']    as String?;
          _admins       = List<String>.from(data['admins'] as List<dynamic>);
          _loadingInfo  = false;
        });
      } else {
        // group doc missing
        setState(() => _loadingInfo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group not found')),
        );
      }
    } catch (e) {
      setState(() => _loadingInfo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to load group info: $e')),
      );
    }
  }

  void _showInviteCode() {
    if (_inviteCode == null) return;
    Clipboard.setData(ClipboardData(text: _inviteCode!));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Invite Code'),
        content: SelectableText(_inviteCode!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTransferDialog() async {
    // load members
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .get();
    final members = List<String>.from(doc['members'] as List<dynamic>);
    final currentOwner = _ownerUid!;
    final candidates = members.where((u) => u != currentOwner).toList();
    String? newOwner = candidates.isNotEmpty ? candidates.first : null;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Transfer Ownership'),
        content: DropdownButtonFormField<String>(
          value: newOwner,
          items: candidates
              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
              .toList(),
          onChanged: (v) => newOwner = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (newOwner != null) {
                FirebaseFirestore.instance
                    .doc('groups/${widget.groupId}')
                    .update({'ownerUid': newOwner});
                setState(() => _ownerUid = newOwner);
              }
              Navigator.pop(context);
            },
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAdminDialog() async {
    // load members
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .get();
    final members = List<String>.from(doc['members'] as List<dynamic>);
    final currentAdmins = Set<String>.from(_admins);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Manage Admins'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: members.map((uid) {
                final isChecked = currentAdmins.contains(uid);
                return CheckboxListTile(
                  title: Text(uid),
                  value: isChecked,
                  onChanged: (v) {
                    setInner(() {
                      if (v == true) currentAdmins.add(uid);
                      else currentAdmins.remove(uid);
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                FirebaseFirestore.instance
                    .doc('groups/${widget.groupId}')
                    .update({'admins': currentAdmins.toList()});
                setState(() => _admins = currentAdmins.toList());
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInfo) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.groupName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // guard missing ownerUid
    if (_ownerUid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.groupName)),
        body: const Center(child: Text('Error loading group owner')),
      );
    }

    final owner = _ownerUid!;
    final isOwner =
        FirebaseAuth.instance.currentUser!.uid == owner;

    final screens = [
      ChatScreen(groupId: widget.groupId),
      FilesScreen(
        groupId:  widget.groupId,
        ownerUid: owner,
        adminUids: _admins,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.vpn_key),
              tooltip: 'Show Invite Code',
              onPressed: _showInviteCode,
            ),
          if (isOwner)
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'transfer') _showTransferDialog();
                else if (action == 'admins') _showAdminDialog();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'transfer',
                    child: Text('Transfer Ownership')),
                PopupMenuItem(
                    value: 'admins',
                    child: Text('Manage Admins')),
              ],
            ),
        ],
      ),
      body: screens[_selected],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selected,
        onTap: (i) => setState(() => _selected = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(
              icon: Icon(Icons.folder), label: 'Files'),
        ],
      ),
    );
  }
}
