import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around connectivity_plus that exposes a simple
/// online/offline boolean stream, and lets other services (like the sync
/// engine) listen for "we just came back online" transitions.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final _onlineController = StreamController<bool>.broadcast();

  /// True/false stream — emits whenever connectivity status changes.
  /// Note: this reflects "has a network interface", not "can actually
  /// reach Firebase" (see isTrulyOnline for that).
  Stream<bool> get onOnlineStatusChanged => _onlineController.stream;

  bool _lastKnownOnline = true;
  bool get lastKnownOnline => _lastKnownOnline;

  Future<void> init() async {
    final initial = await _connectivity.checkConnectivity();
    _lastKnownOnline = _isOnline(initial);

    _subscription =
        _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = _isOnline(results);
      if (isOnline != _lastKnownOnline) {
        _lastKnownOnline = isOnline;
        debugPrint('[ConnectivityService] Status changed: '
            '${isOnline ? "online" : "offline"}');
        _onlineController.add(isOnline);
      }
    });
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// A device can report "online" (Wi-Fi connected) while still having no
  /// real route to the internet (e.g. captive portal, router with no
  /// upstream). This does a cheap real reachability check.
  /// Use this right before a sync attempt, not on
  /// every keystroke — it's a real network call.
  Future<bool> isTrulyOnline(String healthCheckUrl) async {
    if (!_lastKnownOnline) return false;
    try {
      final uri = Uri.parse(healthCheckUrl);
      final result = await Connectivity().checkConnectivity();
      if (_isOnline(result) == false) return false;
      // A lightweight HEAD-style reachability check is left to the caller
      // (e.g. SyncService) since it already has an authenticated client;
      // this method only confirms the OS-level interface state.
      return uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _onlineController.close();
  }
}