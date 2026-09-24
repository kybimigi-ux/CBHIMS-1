import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/hardware_context.dart';
import '../services/hardware_service.dart';
import '../screens/hardware_settings_screen.dart';
import '../screens/dialogs_screen/switch_workspace_dialog.dart';

class NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const NavItem(
      {required this.label, required this.icon, required this.activeIcon});
}

const List<NavItem> kNavItems = [
  NavItem(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded),
  NavItem(
      label: 'Inventory',
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded),
  NavItem(
      label: 'Transactions',
      icon: Icons.call_received_rounded,
      activeIcon: Icons.call_received_rounded),
  NavItem(
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart_rounded),
  NavItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded),
  NavItem(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded),
];

class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const Sidebar(
      {super.key, required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppColors.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBrand(context),
            _buildHardwareChip(context),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: kNavItems.length,
                itemBuilder: (context, index) {
                  final item = kNavItems[index];
                  final selected = index == selectedIndex;
                  return _NavTile(
                    item: item,
                    selected: selected,
                    onTap: () => onSelect(index),
                  );
                },
              ),
            ),
            _buildSwitchHardwareButton(context),
            _buildUserFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBrand(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Container(
            width: 47,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Image.asset('assets/images/clogo.png'),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('STOKADO', style: AppTextStyles.h3),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareChip(BuildContext context) {
    return ListenableBuilder(
      listenable: HardwareContext.instance,
      builder: (context, _) {
        final hw = HardwareContext.instance.activeHardware;
        if (hw == null) return const SizedBox.shrink();
        final isAdmin = AuthService.instance.isAdmin;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final scaffold = Scaffold.maybeOf(context);
                      await SwitchWorkspaceDialog.show(context);
                      scaffold?.closeDrawer();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_rounded,
                              size: 15, color: AppColors.primary),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              hw.name,
                              style: AppTextStyles.label
                                  .copyWith(color: AppColors.primary, fontSize: 11.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.unfold_more_rounded,
                              size: 14, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (isAdmin) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            _HardwareSettingsRouteWrapper(hardwareId: hw.id),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(Icons.settings_outlined,
                        size: 14, color: AppColors.primary),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSwitchHardwareButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () async {
            final scaffold = Scaffold.maybeOf(context);
            await SwitchWorkspaceDialog.show(context);
            scaffold?.closeDrawer();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    size: 17, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Switch Workspace',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary, fontSize: 13.5)),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserFooter(BuildContext context) {
    final auth = AuthService.instance;
    final name = auth.displayName;
    final email = auth.email;
    final isAdmin = auth.isAdmin;
    // Build initials from the display name (up to 2 letters).
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(5),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        initials.isNotEmpty ? initials : 'U',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(name,
                                    style: AppTextStyles.bodyMedium,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isAdmin
                                      ? AppColors.primarySoft
                                      : AppColors.neutralSoft,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isAdmin ? 'Owner' : 'Staff',
                                  style: AppTextStyles.label.copyWith(
                                    color: isAdmin
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(email,
                              style: AppTextStyles.caption,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Log Out',
            icon: const Icon(Icons.logout_rounded,
                size: 18, color: AppColors.textSecondary),
            splashRadius: 18,
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      const Icon(Icons.logout_rounded,
                          color: AppColors.danger, size: 22),
                      const SizedBox(width: 10),
                      Text('Log Out', style: AppTextStyles.h3),
                    ],
                  ),
                  content: Text(
                    'Are you sure you want to log out? You can switch between Store Owner and Staff upon returning to the portal.',
                    style: AppTextStyles.body,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('Cancel',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Log Out'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await AuthService.instance.signOut();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile(
      {required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool active = selected;
    final Color bg = active ? AppColors.primarySoft : Colors.transparent;
    final Color fg = active ? AppColors.primary : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(active ? item.activeIcon : item.icon, size: 19, color: fg),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: AppTextStyles.bodyLarge.copyWith(
                  color:
                      active ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapper that re-fetches the hardware by ID and opens settings.
/// Needed because the sidebar only has the hardware ID from context.
class _HardwareSettingsRouteWrapper extends StatefulWidget {
  final String hardwareId;
  const _HardwareSettingsRouteWrapper({required this.hardwareId});

  @override
  State<_HardwareSettingsRouteWrapper> createState() =>
      _HardwareSettingsRouteWrapperState();
}

class _HardwareSettingsRouteWrapperState
    extends State<_HardwareSettingsRouteWrapper> {
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final hw = await HardwareService.instance.getById(widget.hardwareId);
    if (!mounted) return;
    if (hw == null) {
      Navigator.of(context).pop();
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HardwareSettingsScreen(hardware: hw)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
