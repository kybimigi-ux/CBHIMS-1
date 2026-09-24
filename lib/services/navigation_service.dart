import 'package:flutter/material.dart';

/// Global navigation service that provides access to the root [NavigatorState].
/// Allows performing top-level navigation operations (such as popping all pushed
/// screens back to the authentication root on logout) without requiring a local BuildContext.
class NavigationService {
  NavigationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Returns the current root [BuildContext], if available.
  static BuildContext? get currentContext => navigatorKey.currentContext;

  /// Safely dismisses any open dialogs, drawers, and pushed routes,
  /// returning to the root route (AuthGate / LoginScreen).
  static void popToRoot() {
    final state = navigatorKey.currentState;
    if (state != null && state.canPop()) {
      state.popUntil((route) => route.isFirst);
    }
  }
}
