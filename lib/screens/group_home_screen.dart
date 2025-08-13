// lib/screens/group_home_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_screen.dart';
import 'files_screen.dart';

// ---- Last pane memory (inline to keep this file self-contained) ----
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

// ---- GroupHomeScreen with bottom navigation ----
class GroupHomeScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;

  // If you don't track these here, you can delete these two lines
  final String? ownerUid;
  final List<String>? adminUids;

  const GroupHomeScreen({
    super.key,
    required this.groupId,
    this.groupName,
    this.ownerUid, // ← remove if you don't have them here
    this.adminUids, // ← remove if you don't have them here
  });

  @override
  State<GroupHomeScreen> createState() => _GroupHomeScreenState();
}

class _GroupHomeScreenState extends State<GroupHomeScreen> {
  int _index = 0; // 0 = Chat, 1 = Files
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _restoreLastPane();
  }

  Future<void> _restoreLastPane() async {
    final pane = await LastPaneStore.get(widget.groupId) ?? LastPane.chat;
    if (!mounted) return;
    setState(() {
      _index = pane == LastPane.files ? 1 : 0;
      _initialized = true;
    });
  }

  void _onTap(int i) {
    if (_index == i) return;
    setState(() => _index = i);
    LastPaneStore.set(widget.groupId, i == 1 ? LastPane.files : LastPane.chat);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // NOTE: If ChatScreen only accepts groupId, pass only that.
    final chat = ChatScreen(groupId: widget.groupId);

    // FilesScreen accepts more; pass what you have. If you don't have ownerUid/adminUids here,
    // just remove those named args.
    final files = FilesScreen(
      groupId: widget.groupId,
      groupName: widget.groupName,
      ownerUid: widget.ownerUid, // ← remove if not available here
      adminUids: widget.adminUids, // ← remove if not available here
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName ?? 'Group'),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          chat,
          files,
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_open),
            label: 'Files',
          ),
        ],
      ),
    );
  }
}
