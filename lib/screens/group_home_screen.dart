// lib/screens/group_home_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // for Timestamp
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

  DateTime? _deletionTs;
  Timer? _ticker;

  // UID → displayName map
  Map<String, String> _uidToName = {};
  bool _loadingNames = true;

  @override
  void initState() {
    super.initState();
    _fetchGroupInfo();

    // ─── NEW: tick every minute, update countdown and auto‐pop on expiry ───
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_deletionTs == null) return;
      final now = DateTime.now();
      // **pop exactly at deletion time**
      if (!now.isBefore(_deletionTs!)) {
        // clear the banner and pop the screen
        ScaffoldMessenger.of(context).clearMaterialBanners();
        if (mounted) Navigator.of(context).pop();
      } else {
        // still counting down
        setState(() {});
      }
    });
  }

  @override
  void deactivate() {
    super.deactivate();
    // schedule a banner-clear after this frame, if there's a messenger
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final msgr = ScaffoldMessenger.maybeOf(context);
      msgr?.clearMaterialBanners();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _fetchGroupInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
      final data = doc.data();
      if (data != null) {
        final ts = data['deletionTimestamp'] as Timestamp?;
        setState(() {
          _inviteCode = data['inviteCode'] as String?;
          _ownerUid = data['ownerUid'] as String?;
          _admins = List<String>.from(data['admins'] as List);
          _deletionTs = ts?.toDate();
          _loadingInfo = false;
        });
        await _loadUserNames();
      } else {
        setState(() => _loadingInfo = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Group not found')));
      }
    } catch (e) {
      setState(() => _loadingInfo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to load group info: $e')),
      );
    }
  }

  Future<void> _loadUserNames() async {
    if (_ownerUid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
      final members = List<String>.from(doc['members'] as List);
      final admins = List<String>.from(doc['admins'] as List);
      final owner = doc['ownerUid'] as String;
      final uids = {...members, ...admins, owner}.toList();

      final Map<String, String> map = {};
      for (var i = 0; i < uids.length; i += 10) {
        final chunk =
            uids.sublist(i, i + 10 > uids.length ? uids.length : i + 10);
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (var u in snap.docs) {
          map[u.id] = u['displayName'] as String? ?? u.id;
        }
      }

      setState(() {
        _uidToName = map;
        _loadingNames = false;
      });
    } catch (e) {
      setState(() => _loadingNames = false);
      debugPrint('⚠️ Failed to load user names: $e');
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
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _confirmDeletion() async {
    final ctrl = TextEditingController();
    bool isMatch = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Delete "${widget.groupName}"?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Type the group name to confirm deletion:'),
                TextField(
                  controller: ctrl,
                  onChanged: (value) =>
                      setState(() => isMatch = value == widget.groupName),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: isMatch ? () => Navigator.pop(context, true) : null,
                child: const Text('Schedule Delete'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    final ts = Timestamp.fromDate(
      // For testing: 1 minute. Change back to days when ready.
      DateTime.now().add(const Duration(minutes: 1)),
    );
    print('🔔 Scheduling deletion at $ts');
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .update({'deletionTimestamp': ts});
    setState(() => _deletionTs = ts.toDate());
  }

  Future<void> _undoDeletion() async {
    final me = FirebaseAuth.instance.currentUser!.uid;
    if (me != _ownerUid) return; // extra guard
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .update({'deletionTimestamp': null});
    setState(() => _deletionTs = null);
  }

  String _formatRemaining() {
    if (_deletionTs == null) return '';
    final diff = _deletionTs!.difference(DateTime.now());
    if (diff.inDays >= 1) {
      return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} left';
    } else if (diff.inHours >= 1) {
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} left';
    } else if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} minute${diff.inMinutes > 1 ? 's' : ''} left';
    } else {
      return 'Less than a minute left';
    }
  }

  Future<void> _showTransferDialog() async {
    if (_loadingNames) return;
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .get();
    final members = List<String>.from(doc['members'] as List);
    final currentOwner = _ownerUid!;
    final candidates = members.where((u) => u != currentOwner).toList();
    String? newOwner = candidates.isNotEmpty ? candidates.first : null;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Transfer Ownership'),
        content: DropdownButtonFormField<String>(
          value: newOwner,
          items: candidates.map((u) {
            final name = _uidToName[u] ?? u;
            return DropdownMenuItem(value: u, child: Text(name));
          }).toList(),
          onChanged: (v) => newOwner = v,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: newOwner == null
                ? null
                : () {
                    FirebaseFirestore.instance
                        .collection('groups')
                        .doc(widget.groupId)
                        .update({'ownerUid': newOwner});
                    setState(() => _ownerUid = newOwner);
                    Navigator.pop(context);
                  },
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAdminDialog() async {
    if (_loadingNames) return;
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .get();
    final members = List<String>.from(doc['members'] as List)
        .where((u) => u != _ownerUid)
        .toList();
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
                final name = _uidToName[uid] ?? uid;
                return CheckboxListTile(
                  title: Text(name),
                  value: isChecked,
                  onChanged: (v) {
                    setInner(() {
                      if (v == true)
                        currentAdmins.add(uid);
                      else
                        currentAdmins.remove(uid);
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                FirebaseFirestore.instance
                    .collection('groups')
                    .doc(widget.groupId)
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
    if (_ownerUid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.groupName)),
        body: const Center(child: Text('Error loading group owner')),
      );
    }

    final owner = _ownerUid!;
    final current = FirebaseAuth.instance.currentUser!.uid;
    final isOwner = current == owner;

    // show or clear banner each build
    if (_deletionTs != null && DateTime.now().isBefore(_deletionTs!)) {
      final banner = MaterialBanner(
        content: Text(_formatRemaining()),
        actions: [
          if (isOwner)
            TextButton(onPressed: _undoDeletion, child: const Text('Undo'))
          else
            TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).clearMaterialBanners(),
              child: const Text('Dismiss'),
            ),
        ],
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showMaterialBanner(banner);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).clearMaterialBanners();
      });
    }

    final screens = [
      ChatScreen(groupId: widget.groupId),
      FilesScreen(
        groupId: widget.groupId,
        groupName: widget.groupName,
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
                switch (action) {
                  case 'transfer':
                    _showTransferDialog();
                    break;
                  case 'admins':
                    _showAdminDialog();
                    break;
                  case 'schedule_delete':
                    _confirmDeletion();
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'transfer', child: Text('Transfer Ownership')),
                PopupMenuItem(value: 'admins', child: Text('Manage Admins')),
                PopupMenuItem(
                    value: 'schedule_delete', child: Text('Delete Group')),
              ],
            ),
        ],
      ),
      body: screens[_selected],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selected,
        onTap: (i) => setState(() => _selected = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Files'),
        ],
      ),
    );
  }
}
