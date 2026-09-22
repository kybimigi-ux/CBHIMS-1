import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/hardware.dart';
import 'auth_service.dart';

/// Firestore-backed service for hardware workspace CRUD operations.
class HardwareService {
  HardwareService._();
  static final HardwareService instance = HardwareService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _col => _db.collection('hardwares');

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------

  /// Create a new hardware workspace. The creator is automatically added as admin.
  Future<Hardware> createHardware({
    required String name,
    String description = '',
  }) async {
    final auth = AuthService.instance;
    final uid = auth.userId!;
    final email = auth.email.toLowerCase().trim();
    final fullName = auth.displayName;

    final memberData = {
      'email': email,
      'fullName': fullName,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
    };

    final ref = await _col.add({
      'name': name.trim(),
      'description': description.trim(),
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'memberIds': [uid],
      'members': {uid: memberData},
      'invitedEmails': [],
    });

    final doc = await ref.get();
    return Hardware.fromFirestore(doc);
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns all hardwares the current user belongs to (after auto-accepting invites).
  Future<List<Hardware>> getMyHardwares() async {
    final uid = AuthService.instance.userId;
    final email = AuthService.instance.email.toLowerCase().trim();
    if (uid == null) return [];

    // Accept any pending invites first, then query by memberIds
    await _acceptPendingInvites(uid: uid, email: email);

    try {
      final snap = await _col.where('memberIds', arrayContains: uid).get();
      final list = snap.docs.map((d) => Hardware.fromFirestore(d)).toList();
      list.sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    } catch (e) {
      debugPrint('[HardwareService] getMyHardwares error: $e');
      return [];
    }
  }

  /// Auto-accept pending email invites: moves user from invitedEmails → members.
  Future<void> _acceptPendingInvites({
    required String uid,
    required String email,
  }) async {
    if (email.isEmpty) return;
    try {
      final snap =
          await _col.where('invitedEmails', arrayContains: email).get();
      for (final doc in snap.docs) {
        final hw = Hardware.fromFirestore(doc);
        if (!hw.memberIds.contains(uid)) {
          final memberData = {
            'email': email,
            'fullName': AuthService.instance.displayName,
            'role': 'staff',
            'joinedAt': FieldValue.serverTimestamp(),
          };
          await _col.doc(doc.id).update({
            'memberIds': FieldValue.arrayUnion([uid]),
            'members.$uid': memberData,
            'invitedEmails': FieldValue.arrayRemove([email]),
          });
          debugPrint('[HardwareService] Auto-accepted invite to ${hw.name}');
        }
      }
    } catch (e) {
      debugPrint('[HardwareService] _acceptPendingInvites error: $e');
    }
  }

  /// Fetch a single hardware workspace by ID.
  Future<Hardware?> getById(String hardwareId) async {
    try {
      final doc = await _col.doc(hardwareId).get();
      if (!doc.exists) return null;
      return Hardware.fromFirestore(doc);
    } catch (e) {
      debugPrint('[HardwareService] getById error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  /// Update a hardware workspace name and description.
  Future<void> updateHardware(
    String hardwareId, {
    required String name,
    String description = '',
  }) async {
    await _col.doc(hardwareId).update({
      'name': name.trim(),
      'description': description.trim(),
    });
  }

  /// Invite a member by email. The invite will be accepted next time they log in.
  Future<void> inviteMemberByEmail(String hardwareId, String email) async {
    final normalizedEmail = email.toLowerCase().trim();
    await _col.doc(hardwareId).update({
      'invitedEmails': FieldValue.arrayUnion([normalizedEmail]),
    });
  }

  /// Remove a pending email invite.
  Future<void> removeInvite(String hardwareId, String email) async {
    await _col.doc(hardwareId).update({
      'invitedEmails': FieldValue.arrayRemove([email.toLowerCase().trim()]),
    });
  }

  /// Remove an existing member from a workspace.
  Future<void> removeMember(String hardwareId, String userId) async {
    await _col.doc(hardwareId).update({
      'memberIds': FieldValue.arrayRemove([userId]),
      'members.$userId': FieldValue.delete(),
    });
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Permanently delete a hardware workspace.
  Future<void> deleteHardware(String hardwareId) async {
    await _col.doc(hardwareId).delete();
  }
}
