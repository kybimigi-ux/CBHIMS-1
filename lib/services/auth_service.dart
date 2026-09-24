import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hardware_context.dart';
import 'navigation_service.dart';

class PendingApprovalException implements Exception {
  @override
  String toString() => 'Your account is pending approval by an administrator.';
}

/// Thin wrapper around Firebase Auth + Firestore that every screen can import
/// without coupling directly to the Firebase SDK.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _kSessionLoginTime = 'auth_session_login_time';
  static const _kCachedRole = 'auth_cached_role';

  /// Initialize session & persistence settings (e.g. on web)
  Future<void> init() async {
    if (kIsWeb) {
      try {
        await _auth.setPersistence(Persistence.LOCAL);
      } catch (e) {
        debugPrint('[AuthService] setPersistence error: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Reactive session stream
  // ---------------------------------------------------------------------------

  /// Emits whenever the auth state changes (sign-in, sign-out, token refresh).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// The currently authenticated user, or `null` if signed out.
  User? get currentUser => _auth.currentUser;

  /// Convenience — the user's display name.
  String get displayName => currentUser?.displayName ?? 'User';

  /// Convenience — the user's email.
  String get email => currentUser?.email ?? '';

  /// Convenience — the current user's UID.
  String? get userId => currentUser?.uid;

  String? _cachedRole;
  bool _isRoleLoading = false;
  Future<String?>? _roleFetchFuture;

  /// Cached user role ('Admin', 'Manager', 'Staff'), or null if not yet loaded.
  String? get userRole => _cachedRole;

  /// True while a role fetch is in flight.
  bool get isRoleLoading => _isRoleLoading;

  void _resetRole() {
    _cachedRole = null;
    _isRoleLoading = false;
    _roleFetchFuture = null;
    notifyListeners();
  }

  /// Checks if the session is still within the 1-week (7-day) limit.
  /// If older than 7 days, signs out the user and returns false.
  /// Otherwise, keeps the user signed in and returns true.
  Future<bool> checkSessionValidity() async {
    final user = currentUser;
    if (user == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final loginTimeMs = prefs.getInt(_kSessionLoginTime);

      if (loginTimeMs == null) {
        // Record current timestamp for existing sessions without a timestamp
        await prefs.setInt(
            _kSessionLoginTime, DateTime.now().millisecondsSinceEpoch);
        return true;
      }

      final loginDate = DateTime.fromMillisecondsSinceEpoch(loginTimeMs);
      final difference = DateTime.now().difference(loginDate);

      // 1-week session lifespan limit: 7 days
      if (difference.inDays >= 7) {
        debugPrint(
            '[AuthService] 1-week session expired (${difference.inDays} days old). Signing out.');
        await signOut();
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[AuthService] checkSessionValidity error: $e');
      return true;
    }
  }

  /// Fetch user role from the `users` Firestore collection.
  Future<String?> fetchUserRole({bool forceRefresh = false}) async {
    final uid = userId;
    if (uid == null) {
      _resetRole();
      return null;
    }

    if (!forceRefresh && _cachedRole != null) return _cachedRole;

    // Load from local preferences first to avoid flicker or premature pending screen
    if (!forceRefresh && _cachedRole == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final local = prefs.getString(_kCachedRole);
        if (local != null && local.isNotEmpty) {
          _cachedRole = local;
        }
      } catch (_) {}
    }

    if (_roleFetchFuture != null) return _roleFetchFuture!;

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
      final doc = await _db
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 15));

      if (doc.exists && doc.data()?['role'] != null) {
        final r = doc.data()!['role'].toString().trim();
        _cachedRole = r.isNotEmpty
            ? r[0].toUpperCase() + r.substring(1).toLowerCase()
            : null;
        if (_cachedRole != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kCachedRole, _cachedRole!);
        }
      } else {
        // Fallback for demo accounts if user doc creation was delayed
        if (currentUser?.email == _demoAdminEmail) {
          _cachedRole = 'Admin';
        } else if (currentUser?.email == _demoStaffEmail) {
          _cachedRole = 'Staff';
        } else {
          _cachedRole = null;
          debugPrint('[AuthService] uid=$uid has no approved role yet');
        }
      }
    } catch (e) {
      debugPrint('[AuthService] Could not fetch user role: $e');
      // Fallback to local cache or demo role
      if (_cachedRole == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          _cachedRole = prefs.getString(_kCachedRole);
        } catch (_) {}
        if (_cachedRole == null) {
          if (currentUser?.email == _demoAdminEmail) {
            _cachedRole = 'Admin';
          } else if (currentUser?.email == _demoStaffEmail) {
            _cachedRole = 'Staff';
          }
        }
      }
    } finally {
      _isRoleLoading = false;
      notifyListeners();
    }

    return _cachedRole;
  }

  /// True if the user has signed up but has not yet been assigned a role.
  bool get isPending =>
      currentUser != null && _cachedRole == null && !_isRoleLoading;

  /// Check if the logged in user is an Admin.
  bool get isAdmin => (_cachedRole ?? '').toLowerCase() == 'admin';

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Update user's role in the `users` Firestore collection (Admin action).
  Future<void> updateUserRole(String targetUserId, String newRole) async {
    final formattedRole = newRole.toLowerCase();
    await _db
        .collection('users')
        .doc(targetUserId)
        .update({'role': formattedRole}).timeout(const Duration(seconds: 8));
    if (targetUserId == userId) {
      _cachedRole =
          formattedRole[0].toUpperCase() + formattedRole.substring(1);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kCachedRole, _cachedRole!);
      } catch (_) {}
      notifyListeners();
    }
  }

  /// Update display name / profile info.
  Future<void> updateProfile({required String fullName}) async {
    final uid = userId;
    if (uid != null) {
      // 1. Update Firebase Auth display name
      await currentUser!
          .updateDisplayName(fullName)
          .timeout(const Duration(seconds: 8));
      // 2. Update Firestore users document
      await _db.collection('users').doc(uid).set({
        'full_name': fullName,
        'email': email,
        'role': (_cachedRole ?? 'Staff').toLowerCase(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
      notifyListeners();
    }
  }

  /// Update user password.
  Future<void> updatePassword(String newPassword) async {
    await currentUser!
        .updatePassword(newPassword)
        .timeout(const Duration(seconds: 8));
  }

  /// Create a new account with email, password and a display name.
  /// Also inserts a document into the `users` Firestore collection.
  /// New users get 'staff' role by default (or 'admin' if they're the first user).
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String fullName,
    String role = 'staff',
  }) async {
    _resetRole();

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user != null) {
      // Set display name in Firebase Auth
      try {
        await user.updateDisplayName(fullName);
      } catch (e) {
        debugPrint('[AuthService] Could not update display name: $e');
      }

      String assignedRole = role.toLowerCase().trim();
      if (assignedRole.isEmpty) {
        assignedRole = 'staff';
      }

      // Insert user profile in Firestore
      try {
        await _db.collection('users').doc(user.uid).set({
          'full_name': fullName,
          'email': email,
          'role': assignedRole,
          'created_at': FieldValue.serverTimestamp(),
        });
        final formatted = assignedRole[0].toUpperCase() + assignedRole.substring(1).toLowerCase();
        _cachedRole = formatted;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(
              _kSessionLoginTime, DateTime.now().millisecondsSinceEpoch);
          await prefs.setString(_kCachedRole, formatted);
        } catch (_) {}
      } catch (e) {
        debugPrint('[AuthService] Failed to create user document: $e');
      }

      notifyListeners();
    }

    return credential;
  }


  /// Sign in with email & password.
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    _resetRole();

    final credential = await _auth
        .signInWithEmailAndPassword(email: email, password: password)
        .timeout(const Duration(seconds: 10));

    if (credential.user != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            _kSessionLoginTime, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
      await fetchUserRole(forceRefresh: true);
    }

    return credential;
  }

  /// End the current session.
  Future<void> signOut() async {
    HardwareContext.instance.clearActiveHardware();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSessionLoginTime);
      await prefs.remove(_kCachedRole);
    } catch (_) {}
    try {
      await _auth.signOut().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[AuthService] signOut error: $e');
    }
    _resetRole();

    // Pop all pushed routes back to the root AuthGate, ensuring any pushed
    // screens (like MainLayoutScreen, dialogs, drawers) are fully dismissed.
    NavigationService.popToRoot();
  }

  // ---------------------------------------------------------------------------
  // Demo Login
  // ---------------------------------------------------------------------------

  static const _demoAdminEmail = 'demo-admin@stokado.app';
  static const _demoStaffEmail = 'demo-staff@stokado.app';
  static const _demoAdminPassword = 'DemoAdmin123!';
  static const _demoStaffPassword = 'DemoStaff123!';

  /// Sign in as a demo account. Auto-creates the account if it doesn't exist.
  Future<void> signInDemo({required String role}) async {
    final email = role == 'admin' ? _demoAdminEmail : _demoStaffEmail;
    final password = role == 'admin' ? _demoAdminPassword : _demoStaffPassword;
    try {
      await signIn(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      // Firebase newer SDK returns 'invalid-credential' for both "no user" and
      // "wrong password". We treat it as "account may not exist" and try to
      // create it. If it already exists, we catch email-already-in-use and
      // re-attempt sign-in (handles edge cases like stale passwords).
      if (e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'INVALID_LOGIN_CREDENTIALS' ||
          e.code == 'wrong-password') {
        try {
          await _createDemoAccount(email: email, password: password, role: role);
        } on FirebaseAuthException catch (createError) {
          if (createError.code == 'email-already-in-use') {
            // Account exists — force delete and recreate isn't an option,
            // so we surface a friendly error instead.
            throw FirebaseAuthException(
              code: 'demo-sign-in-failed',
              message:
                  'Demo account exists but could not be signed into. '
                  'Please try again or contact support.',
            );
          }
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  Future<void> _createDemoAccount({
    required String email,
    required String password,
    required String role,
  }) async {
    _resetRole();
    final credential = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    final user = credential.user;
    if (user == null) return;
    final fullName = role == 'admin' ? 'Demo Admin' : 'Demo Staff';
    try {
      await user.updateDisplayName(fullName);
    } catch (_) {}
    await _db.collection('users').doc(user.uid).set({
      'full_name': fullName,
      'email': email,
      'role': role,
      'created_at': FieldValue.serverTimestamp(),
      'is_demo': true,
    });
    _cachedRole = role == 'admin' ? 'Admin' : 'Staff';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _kSessionLoginTime, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString(_kCachedRole, _cachedRole!);
    } catch (_) {}
    notifyListeners();
  }

  /// Fetch all users from Firestore (admin usage).
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final snap = await _db
        .collection('users')
        .get()
        .timeout(const Duration(seconds: 10));
    return snap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();
  }
}