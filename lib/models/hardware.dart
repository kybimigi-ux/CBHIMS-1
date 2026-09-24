import 'package:cloud_firestore/cloud_firestore.dart';

/// Permissions assigned to a member within a hardware workspace.
class MemberPermissions {
  final bool canAddProducts;
  final bool canEditProducts;
  final bool canRemoveProducts;
  final bool canAddTransactions;
  final bool canCancelTransactions;

  const MemberPermissions({
    this.canAddProducts = true,
    this.canEditProducts = true,
    this.canRemoveProducts = false,
    this.canAddTransactions = true,
    this.canCancelTransactions = false,
  });

  factory MemberPermissions.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const MemberPermissions();
    return MemberPermissions(
      canAddProducts: data['canAddProducts'] as bool? ?? data['allowAddProducts'] as bool? ?? true,
      canEditProducts: data['canEditProducts'] as bool? ?? data['allowEditProducts'] as bool? ?? true,
      canRemoveProducts: data['canRemoveProducts'] as bool? ?? data['allowRemoveProducts'] as bool? ?? false,
      canAddTransactions: data['canAddTransactions'] as bool? ?? data['allowAddTransactions'] as bool? ?? true,
      canCancelTransactions: data['canCancelTransactions'] as bool? ?? data['allowCancelTransactions'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'canAddProducts': canAddProducts,
        'canEditProducts': canEditProducts,
        'canRemoveProducts': canRemoveProducts,
        'canAddTransactions': canAddTransactions,
        'canCancelTransactions': canCancelTransactions,
      };

  MemberPermissions copyWith({
    bool? canAddProducts,
    bool? canEditProducts,
    bool? canRemoveProducts,
    bool? canAddTransactions,
    bool? canCancelTransactions,
  }) {
    return MemberPermissions(
      canAddProducts: canAddProducts ?? this.canAddProducts,
      canEditProducts: canEditProducts ?? this.canEditProducts,
      canRemoveProducts: canRemoveProducts ?? this.canRemoveProducts,
      canAddTransactions: canAddTransactions ?? this.canAddTransactions,
      canCancelTransactions: canCancelTransactions ?? this.canCancelTransactions,
    );
  }
}

/// A member of a hardware workspace.
class HardwareMember {
  final String userId;
  final String email;
  final String fullName;
  final String role; // 'admin' | 'staff'
  final DateTime? joinedAt;
  final MemberPermissions permissions;

  const HardwareMember({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    this.joinedAt,
    this.permissions = const MemberPermissions(),
  });

  factory HardwareMember.fromMap(String uid, Map<String, dynamic> data) {
    return HardwareMember(
      userId: uid,
      email: data['email'] as String? ?? '',
      fullName: data['fullName'] as String? ?? data['email'] as String? ?? 'User',
      role: data['role'] as String? ?? 'staff',
      joinedAt: _parseDate(data['joinedAt']),
      permissions: MemberPermissions.fromMap(
        data['permissions'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'fullName': fullName,
        'role': role,
        'joinedAt': FieldValue.serverTimestamp(),
        'permissions': permissions.toMap(),
      };

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val);
    return null;
  }

  String get initials {
    final parts = fullName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase());
    final joined = parts.join();
    return joined.isEmpty
        ? (email.isNotEmpty ? email[0].toUpperCase() : 'U')
        : joined;
  }

  bool get isAdmin => role.toLowerCase() == 'admin';

  bool get canAddProducts => isAdmin || permissions.canAddProducts;
  bool get canEditProducts => isAdmin || permissions.canEditProducts;
  bool get canRemoveProducts => isAdmin || permissions.canRemoveProducts;
  bool get canAddTransactions => isAdmin || permissions.canAddTransactions;
  bool get canCancelTransactions => isAdmin || permissions.canCancelTransactions;
}

/// A hardware workspace — the top-level store context that groups users together.
class Hardware {
  final String id;
  final String name;
  final String description;
  final String createdBy;
  final DateTime? createdAt;
  final List<String> memberIds;
  final Map<String, HardwareMember> members;
  final List<String> invitedEmails;

  const Hardware({
    required this.id,
    required this.name,
    required this.description,
    required this.createdBy,
    this.createdAt,
    required this.memberIds,
    required this.members,
    required this.invitedEmails,
  });

  factory Hardware.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final membersRaw = data['members'] as Map<String, dynamic>? ?? {};
    final members = membersRaw.map(
      (uid, memberData) => MapEntry(
        uid,
        HardwareMember.fromMap(
            uid, (memberData as Map<String, dynamic>? ?? {})),
      ),
    );

    return Hardware(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed Hardware',
      description: data['description'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: _parseDate(data['createdAt']),
      memberIds: List<String>.from(data['memberIds'] as List? ?? []),
      members: members,
      invitedEmails: List<String>.from(data['invitedEmails'] as List? ?? []),
    );
  }

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val);
    return null;
  }

  int get memberCount => members.length;

  List<HardwareMember> get memberList {
    final list = members.values.toList();
    list.sort((a, b) {
      if (a.isAdmin && !b.isAdmin) return -1;
      if (!a.isAdmin && b.isAdmin) return 1;
      return a.fullName.compareTo(b.fullName);
    });
    return list;
  }
}
