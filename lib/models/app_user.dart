class AppUser {
  final String id; // UUID from auth.users
  final String fullName;
  final String email;
  final String? role; // 'Admin', 'Manager', 'Staff'
  final DateTime? createdAt;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.role,
    this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      // Handle Firestore Timestamp
      if (val.runtimeType.toString().contains('Timestamp')) {
        try {
          return (val as dynamic).toDate() as DateTime;
        } catch (_) {}
      }
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return AppUser(
      id: json['id'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String?,
      createdAt: parseDate(json['created_at']),
    );
  }

  /// Initials from the full name (up to 2 letters).
  String get initials {
    final parts = fullName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase());
    return parts.join();
  }
}
