import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_screen/login_screen.dart';
import 'auth_screen/pending_approval_screen.dart';
import 'main_layout_screen.dart';
import '../services/auth_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await AuthService.instance.fetchUserRole();
    }
    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  Widget _resolveHome() {
    if (AuthService.instance.isPending) {
      return const PendingApprovalScreen();
    }
    return const MainLayoutScreen();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return ListenableBuilder(
          listenable: AuthService.instance,
          builder: (context, _) {
            if (AuthService.instance.isRoleLoading &&
                AuthService.instance.userRole == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return _resolveHome();
          },
        );
      },
    );
  }
}