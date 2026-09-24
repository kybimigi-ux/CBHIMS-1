import 'package:flutter/foundation.dart';
import '../models/hardware.dart';
import 'auth_service.dart';

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

  /// Current user as a member of the active hardware workspace.
  HardwareMember? get currentMember {
    final uid = AuthService.instance.userId;
    if (uid == null || _activeHardware == null) return null;
    return _activeHardware!.members[uid];
  }

  /// Whether the current user is an Admin/Store Owner in this workspace or globally.
  bool get isCurrentAdmin {
    final uid = AuthService.instance.userId;
    if (uid == null) return false;
    if (AuthService.instance.isAdmin) return true;
    if (_activeHardware?.createdBy == uid) return true;
    return currentMember?.isAdmin ?? false;
  }

  /// Whether current user is allowed to add new products.
  bool get canAddProducts =>
      isCurrentAdmin || (currentMember?.canAddProducts ?? false);

  /// Whether current user is allowed to edit existing products.
  bool get canEditProducts =>
      isCurrentAdmin || (currentMember?.canEditProducts ?? false);

  /// Whether current user is allowed to remove/delete products.
  bool get canRemoveProducts =>
      isCurrentAdmin || (currentMember?.canRemoveProducts ?? false);

  /// Whether current user is allowed to add transactions (Receive / Release).
  bool get canAddTransactions =>
      isCurrentAdmin || (currentMember?.canAddTransactions ?? false);

  /// Whether current user is allowed to cancel/delete transactions.
  bool get canCancelTransactions =>
      isCurrentAdmin || (currentMember?.canCancelTransactions ?? false);
}
