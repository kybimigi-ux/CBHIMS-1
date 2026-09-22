import 'package:flutter/foundation.dart';
import '../models/hardware.dart';

/// Singleton ChangeNotifier that holds the currently active hardware workspace.
/// Screens and widgets can listen to this to know which workspace is selected.
class HardwareContext extends ChangeNotifier {
  HardwareContext._();
  static final HardwareContext instance = HardwareContext._();

  Hardware? _activeHardware;

  /// The currently selected hardware workspace, or null if none is selected.
  Hardware? get activeHardware => _activeHardware;

  /// Whether a hardware workspace is currently active.
  bool get hasActiveHardware => _activeHardware != null;

  /// Set the active hardware workspace and notify listeners.
  void setActiveHardware(Hardware hardware) {
    _activeHardware = hardware;
    notifyListeners();
  }

  /// Refresh the active hardware with an updated snapshot.
  void refreshActiveHardware(Hardware hardware) {
    if (_activeHardware?.id == hardware.id) {
      _activeHardware = hardware;
      notifyListeners();
    }
  }

  /// Clear the active workspace (e.g. when switching or logging out).
  void clearActiveHardware() {
    _activeHardware = null;
    notifyListeners();
  }
}
