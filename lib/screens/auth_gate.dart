import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
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

    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final session = Supabase.instance.client.auth.currentSession;

        if (session == null || AuthService.instance.currentUser == null) {
          return const LoginScreen();
        }

        if (AuthService.instance.isRoleLoading &&
            AuthService.instance.userRole == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return _resolveHome();
      },
    );
  }
}