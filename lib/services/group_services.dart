// In your GroupService (lib/services/group_service.dart)
import 'package:cloud_firestore/cloud_firestore.dart';

class GroupService {
  final CollectionReference _groups = FirebaseFirestore.instance.collection('groups');

  Future<void> createGroup(String groupName, String creatorUid) async {
    await _groups.add({
      'name': groupName,
      'creator': creatorUid,
      'members': [creatorUid],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
  
  // Additional functions: joinGroup, getGroupsForUser, etc.
}
