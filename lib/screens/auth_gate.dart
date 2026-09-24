import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_screen/auth_portal_screen.dart';
import 'hardware_lobby_screen.dart';
import '../services/auth_service.dart';
import '../services/hardware_context.dart';
import '../services/navigation_service.dart';

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
    final isValid = await AuthService.instance.checkSessionValidity();
    if (isValid) {
      await AuthService.instance.fetchUserRole();
    }
    if (mounted) {
      setState(() => _initializing = false);
    }
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
          // Clear active hardware on logout and ensure pushed routes are dismissed
          HardwareContext.instance.clearActiveHardware();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NavigationService.popToRoot();
          });
          return const AuthPortalScreen();
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
            // Always go to the hardware lobby — no pending approval screen.
            return const HardwareLobbyScreen();
          },
        );
      },
    );
  }
}