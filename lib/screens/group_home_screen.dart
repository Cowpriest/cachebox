// lib/screens/group_home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // for Clipboard

import 'chat_screen.dart';
import 'files_screen.dart';
import 'group_list_screen.dart';
import '../services/jellyfin_thumb_service.dart';
import '../services/thumb_cache.dart';

// ---- Last pane memory ----
enum LastPane { chat, files }

class LastPaneStore {
  static String _key(String groupId) => 'last_pane:$groupId';
  static Future<void> set(String groupId, LastPane pane) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key(groupId), pane.name);
  }

  static Future<LastPane?> get(String groupId) async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_key(groupId));
    if (s == null) return null;
    return s == 'files' ? LastPane.files : LastPane.chat;
  }
}

class GroupHomeScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;
  final String? ownerUid;
  final List<String>? adminUids;
  const GroupHomeScreen({
    super.key,
    required this.groupId,
    this.groupName,
    this.ownerUid,
    this.adminUids,
  });

  @override
  State<GroupHomeScreen> createState() => _GroupHomeScreenState();
}

class _GroupHomeScreenState extends State<GroupHomeScreen> {
  // Google nickname if available, else email/uid
  String _currentUserLabel() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return '';
    final name = (u.displayName ?? '').trim();
    if (name.isNotEmpty) return name;
    return u.email ?? u.uid;
  }

  // Upload function handed up from FilesScreen
  //Future<void> Function()? _triggerUpload;

  late final PageController _pageController;
  bool _suppressInitialChange = false;

  // Files tab back handler (provided by FilesScreen)
  Future<bool> Function()? _filesBackHandler;
  int _index = 0; // 0 = Chat, 1 = Files
  bool _initialized = false;

  String? _inviteCode;
  String? _ownerUid;
  List<String> _admins = [];
  bool _loadingInfo = true;
  Map<String, String> _uidToName = {};
  bool _loadingNames = true;

  DateTime? _deletionTs;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _restoreLastPane();
    _primeOwnerFromArgsThenFetch();
    //_pageController = PageController(initialPage: _index);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_deletionTs != null && DateTime.now().isAfter(_deletionTs!)) {
        if (mounted) setState(() => _deletionTs = null);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _restoreLastPane() async {
    final pane = await LastPaneStore.get(widget.groupId) ?? LastPane.chat;
    final idx = pane == LastPane.files ? 1 : 0;

    // Create controller WITH the restored page
    _pageController = PageController(initialPage: idx);
    _suppressInitialChange = true;

    if (!mounted) return;
    setState(() {
      _index = idx;
      _initialized = true;
    });
  }

  Future<void> _primeOwnerFromArgsThenFetch() async {
    if (widget.ownerUid != null) {
      _ownerUid = widget.ownerUid;
      _admins = List<String>.from(widget.adminUids ?? const []);
      _loadingInfo = false;
      if (mounted) setState(() {});
    }
    await _fetchGroupInfo();
  }

  Future<void> _fetchGroupInfo() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
      final data = snap.data();
      if (data == null) {
        if (mounted) {
          _loadingInfo = false;
          setState(() {});
        }
        return;
      }
      final ts = data['deletionTimestamp'] as Timestamp?;
      _inviteCode = data['inviteCode'] as String?;
      _ownerUid = (data['ownerUid'] as String?) ?? _ownerUid;
      _admins = List<String>.from((data['admins'] as List?) ?? _admins);
      _deletionTs = ts?.toDate();
      _loadingInfo = false;
      if (mounted) setState(() {});
      await _loadUserNames();
    } catch (e) {
      _loadingInfo = false;
      if (mounted) setState(() {});
      debugPrint('⚠️ Failed to fetch group info: $e');
    }
  }

  Future<void> _loadUserNames() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
      final members = List<String>.from((doc['members'] as List?) ?? const []);
      final admins = List<String>.from((doc['admins'] as List?) ?? const []);
      final owner = (doc['ownerUid'] as String?) ?? '';
      final uids =
          {...members, ...admins, if (owner.isNotEmpty) owner}.toList();
      final Map<String, String> map = {};

      for (var i = 0; i < uids.length; i += 10) {
        final end = (i + 10) > uids.length ? uids.length : (i + 10);
        final chunk = uids.sublist(i, end);
        if (chunk.isEmpty) continue;
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final u in snap.docs) {
          map[u.id] = (u['displayName'] as String?) ?? u.id;
        }
      }

      _uidToName = map;
      _loadingNames = false;
      if (mounted) setState(() {});
    } catch (e) {
      _loadingNames = false;
      if (mounted) setState(() {});
      debugPrint('⚠️ Failed to load user names: $e');
    }
  }

  Future<void> _showInviteCode() async {
    if (_inviteCode == null || _inviteCode!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No invite code available for this group.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: _inviteCode!));
    if (!mounted) return;

    // Optional: small visual confirm (snack) + dialog with selectable code
    // ScaffoldMessenger.of(context).showSnackBar(
    //   const SnackBar(content: Text('Invite code copied')),
    // );

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

  void _onTap(int i) {
    if (_index == i) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    // onPageChanged will update _index + LastPaneStore
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

  void _onMenu(String action) async {
    switch (action) {
      case 'invitecode':
        await _showInviteCode();
        break;
      case 'admins':
        await _showAdminDialog();
        break;
      case 'schedule_delete':
        await _confirmDeletion();
        break;
      case 'transfer':
        await _showTransferDialog();
        break;
      case 'groups':
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop(); // bypasses WillPopScope; returns to Your Groups list
        } else {
          // Optional: handle deep-link case by pushing the list screen
          nav.pushReplacement(
              MaterialPageRoute(builder: (_) => const GroupListScreen()));
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final chat = ChatScreen(groupId: widget.groupId);
    final GlobalKey<FilesScreenState> _filesKey = GlobalKey<FilesScreenState>();
    final files = FilesScreen(
      key: _filesKey,
      groupId: widget.groupId,
      groupName: widget.groupName,
      ownerUid: _ownerUid ?? widget.ownerUid,
      adminUids: _admins.isNotEmpty ? _admins : (widget.adminUids ?? const []),
      // IMPORTANT: make sure your FilesScreen has this optional param.
      registerBackHandler: (fn) => _filesBackHandler = fn,
      //registerUploadAction: (fn) => _triggerUpload = fn,
    );

    final me = FirebaseAuth.instance.currentUser;
    final effectiveOwner = _ownerUid ?? widget.ownerUid;
    final isOwner =
        me != null && effectiveOwner != null && me.uid == effectiveOwner;

    return WillPopScope(
      onWillPop: () async {
        if (_index == 1) {
          final handler = _filesBackHandler;
          if (handler != null) {
            final consumed = await handler();
            if (consumed) return false; // moved up a folder
            return false; // at root: do nothing
          }
        }
        return true; // other tabs: allow normal pop
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 64,
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.groupName ?? 'Group',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _currentUserLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.70),
                    ),
              ),
            ],
          ),
          actions: [
            if (_index == 1) ...[
              // <-- 1 is the Files tab index
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Build thumbnails for this folder',
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Building thumbnails…')),
                    );
                    await _filesKey.currentState
                        ?.refreshCurrentFolderThumbnails();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Thumbnails updated')),
                    );
                  },
                ),
              TextButton(
                onPressed: () {
                  // This guarantees something happens when you tap Upload on the Files tab
                  final st = _filesKey.currentState;
                  if (st == null) {
                    debugPrint(
                        '[GroupHome] FilesScreen state is null – not mounted yet.');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Files not ready yet — try again.')),
                    );
                    return;
                  }
                  debugPrint(
                      '[GroupHome] Calling FilesScreen.pickAndUpload() …');
                  st.pickAndUpload();
                },
                child: Text('Upload'),
              ),
            ],
            PopupMenuButton<String>(
              onSelected: _onMenu,
              itemBuilder: (_) => isOwner
                  ? const [
                      PopupMenuItem(
                          value: 'invitecode', child: Text('Show Invite Code')),
                      PopupMenuItem(
                          value: 'admins', child: Text('Manage Admins')),
                      PopupMenuItem(
                          value: 'transfer', child: Text('Transfer Ownership')),
                      PopupMenuItem(
                          value: 'schedule_delete',
                          child: Text('Delete Group')),
                      PopupMenuItem(
                          value: 'groups', child: Text('Your Groups')),
                    ]
                  : const [
                      PopupMenuItem(
                          value: 'invitecode', child: Text('Show Group Key')),
                      PopupMenuItem(
                          value: 'groups', child: Text('Your Groups')),
                    ],
            ),
          ],
        ),
        body: PageView(
          controller: _pageController,
          physics: const PageScrollPhysics(), // natural swipe
          onPageChanged: (page) {
            if (_index != page) {
              setState(() => _index = page);
              LastPaneStore.set(
                widget.groupId,
                page == 1 ? LastPane.files : LastPane.chat,
              );
            }
          },
          children: [chat, files],
        ),
        // bottomNavigationBar: BottomNavigationBar(
        //   currentIndex: _index,
        //   onTap: _onTap,
        //   items: const [
        //     BottomNavigationBarItem(
        //       icon: Icon(Icons.chat_bubble_outline),
        //       label: 'Chat',
        //     ),
        //     BottomNavigationBarItem(
        //       icon: Icon(Icons.folder_open),
        //       label: 'Files',
        //     ),
        //   ],
        // ),
      ),
    );
  }

  Future<void> _showAdminDialog() async {
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .get();
    final members = List<String>.from((doc['members'] as List?) ?? const [])
        .where((uid) => uid != _ownerUid)
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
              children: [
                if (_loadingNames)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: LinearProgressIndicator(),
                  ),
                ...members.map((uid) {
                  final isChecked = currentAdmins.contains(uid);
                  final name = _uidToName[uid] ?? uid;
                  return CheckboxListTile(
                    title: Text(name),
                    value: isChecked,
                    onChanged: (v) {
                      setInner(() {
                        if (v == true) {
                          currentAdmins.add(uid);
                        } else {
                          currentAdmins.remove(uid);
                        }
                      });
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final list = currentAdmins.toList();
                await FirebaseFirestore.instance
                    .collection('groups')
                    .doc(widget.groupId)
                    .update({'admins': list});
                if (mounted) setState(() => _admins = list);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletion() async {
    final ctrl = TextEditingController();
    bool isMatch = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Delete "${widget.groupName ?? 'this group'}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Type the group name to confirm deletion:'),
              TextField(
                controller: ctrl,
                onChanged: (v) =>
                    setState(() => isMatch = v == (widget.groupName ?? '')),
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
        ),
      ),
    );

    if (ok != true) return;

    final ts = Timestamp.fromDate(
      DateTime.now().add(const Duration(minutes: 1)), // TODO: change to days
    );

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .update({'deletionTimestamp': ts});

    if (mounted) setState(() => _deletionTs = ts.toDate());
  }
}
