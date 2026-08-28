import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PendingApprovalException implements Exception {
  @override
  String toString() => 'Your account is pending approval by an administrator.';
}

/// Thin wrapper around Supabase Auth that every screen can import
/// without coupling directly to the Supabase SDK.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  final SupabaseClient _client = Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Reactive session stream
  // ---------------------------------------------------------------------------

  /// Emits whenever the auth state changes (sign-in, sign-out, token refresh).
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// The currently authenticated user, or `null` if signed out.
  User? get currentUser => _client.auth.currentUser;

  /// Convenience — the user's display name stored in metadata.
  String get displayName =>
      currentUser?.userMetadata?['full_name'] as String? ?? 'User';

  /// Convenience — the user's email.
  String get email => currentUser?.email ?? '';

  /// Convenience — the current user's UUID.
  String? get userId => currentUser?.id;

  String? _cachedRole;
  bool _isRoleLoading = false;
  Future<String?>? _roleFetchFuture;

  /// Cached user role ('Admin', 'Manager', 'Staff'), or null if not yet loaded.
  String? get userRole => _cachedRole;

  /// True while a role fetch is in flight — screens can use this to avoid
  /// flashing an incorrect Admin/Staff button before the real role arrives.
  bool get isRoleLoading => _isRoleLoading;

  /// Clears the cached role. Call this on sign-out and at the start of
  /// sign-in so no screen can ever read a previous user's role.
  void _resetRole() {
    _cachedRole = null;
    _isRoleLoading = false;
    _roleFetchFuture = null;
    notifyListeners();
  }

  /// Fetch user role from the `users` table in Supabase.
  /// Deduplicates in-flight calls and returns cached role when available.
  Future<String?> fetchUserRole({bool forceRefresh = false}) async {
    final uid = userId;
    if (uid == null) {
      _resetRole();
      return null;
    }

    if (!forceRefresh && _cachedRole != null) {
      return _cachedRole;
    }

    if (_roleFetchFuture != null) {
      return _roleFetchFuture!;
    }

    _roleFetchFuture = _doFetchUserRole(uid);
    try {
      final role = await _roleFetchFuture!;
      return role;
    } finally {
      _roleFetchFuture = null;
    }
  }

  Future<String?> _doFetchUserRole(String uid) async {
    _isRoleLoading = true;
    notifyListeners();

    try {
      final res = await _client
          .from('users')
          .select('role, full_name, email')
          .eq('id', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (res != null && res['role'] != null) {
        final r = res['role'].toString().trim();
        _cachedRole = r.isNotEmpty
            ? r[0].toUpperCase() + r.substring(1).toLowerCase()
            : null;
      } else {
        _cachedRole = null;
        debugPrint('[AuthService] uid=$uid has no approved role yet');
      }
    } catch (e) {
      debugPrint('[AuthService] Could not fetch user role: $e');
      _cachedRole = null;
    } finally {
      _isRoleLoading = false;
      notifyListeners();
    }

    return _cachedRole;
  }

  /// True if the user has signed up but has not yet been assigned a role.
  bool get isPending => currentUser != null && _cachedRole == null && !_isRoleLoading;

  /// Check if the logged in user is an Admin.
  bool get isAdmin => (_cachedRole ?? '').toLowerCase() == 'admin';

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Update user's role in the `users` table (Admin action).
  Future<void> updateUserRole(String targetUserId, String newRole) async {
    final formattedRole = newRole.toLowerCase();
    await _client
        .from('users')
        .update({'role': formattedRole})
        .eq('id', targetUserId)
        .timeout(const Duration(seconds: 8));
    if (targetUserId == userId) {
      _cachedRole = formattedRole[0].toUpperCase() + formattedRole.substring(1);
      notifyListeners();
    }
  }

  /// Update display name / profile info.
  Future<void> updateProfile({required String fullName}) async {
    final uid = userId;
    if (uid != null) {
      // 1. Update user metadata in auth
      await _client.auth
          .updateUser(UserAttributes(data: {'full_name': fullName}))
          .timeout(const Duration(seconds: 8));
      // 2. Update users table
      await _client.from('users').upsert({
        'id': uid,
        'full_name': fullName,
        'email': email,
        'role': (_cachedRole ?? 'Staff').toLowerCase(),
      }).timeout(const Duration(seconds: 8));
      notifyListeners();
    }
  }

  /// Update user password.
  Future<void> updatePassword(String newPassword) async {
    await _client.auth
        .updateUser(UserAttributes(password: newPassword))
        .timeout(const Duration(seconds: 8));
  }

  /// Create a new account with email, password and a display name.
  /// Also inserts a row into the `public.users` table.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    _resetRole();

    final response = await _client.auth
        .signUp(
          email: email,
          password: password,
          data: {'full_name': fullName},
        )
        .timeout(const Duration(seconds: 10));

    final user = response.user;
    if (user != null) {
      try {
        await _client.from('users').upsert({
          'id': user.id,
          'full_name': fullName,
          'email': email,
          'role': null, // pending approval — an admin must assign a role
        }).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('[AuthService] Failed to insert into users table: $e');
      }

      try {
        await _client.auth.signOut().timeout(const Duration(seconds: 5));
      } catch (_) {}
      _resetRole();
    }

    return response;
  }

  /// Sign in with email & password.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    _resetRole();

    final response = await _client.auth
        .signInWithPassword(
          email: email,
          password: password,
        )
        .timeout(const Duration(seconds: 10));

    if (response.user != null) {
      await fetchUserRole();
    }

    return response;
  }

  /// End the current session.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[AuthService] signOut error: $e');
    }
    _resetRole();
  }
}