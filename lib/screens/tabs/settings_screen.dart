import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notification_banner.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_badge.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _tab = 0;

  late TextEditingController _appNameController;
  late bool _notificationBanner;
  late bool _lowStockAlerts;
  late bool _inboundNotices;
  late bool _emailSummaries;

  List<AppUser> _team = [];
  bool _loadingTeam = true;

  List<String> get _visibleTabs {
    if (AuthService.instance.isAdmin) {
      return const ['General', 'Notifications', 'User Management'];
    }
    return const ['General', 'Notifications'];
  }

  @override
  void initState() {
    super.initState();
    final settings = SettingsService.instance;
    _appNameController = TextEditingController(text: settings.appName);
    _notificationBanner = settings.notificationBannerEnabled;
    _lowStockAlerts = settings.lowStockAlerts;
    _inboundNotices = settings.inboundNotices;
    _emailSummaries = settings.emailSummaries;

    _loadTeam();
  }

  @override
  void dispose() {
    _appNameController.dispose();
    super.dispose();
  }

  Future<void> _loadTeam() async {
    if (!AuthService.instance.isAdmin) {
      if (mounted) setState(() => _loadingTeam = false);
      return;
    }

    setState(() => _loadingTeam = true);
    try {
      final rawUsers = await AuthService.instance.getAllUsers();

      List<AppUser> users = rawUsers
          .map((row) => AppUser.fromJson(row))
          .toList();

      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        final currentRole = await AuthService.instance.fetchUserRole();
        final idx = users.indexWhere((u) => u.id == current.uid);
        if (idx >= 0) {
          users[idx] = AppUser(
            id: current.uid,
            fullName: users[idx].fullName.isNotEmpty
                ? users[idx].fullName
                : AuthService.instance.displayName,
            email: current.email ?? users[idx].email,
            role: currentRole,
            createdAt: users[idx].createdAt,
          );
        } else {
          users.insert(
            0,
            AppUser(
              id: current.uid,
              fullName: AuthService.instance.displayName,
              email: AuthService.instance.email,
              role: currentRole,
            ),
          );
        }
        // Pin current user to the top
        users.sort((a, b) {
          if (a.id == current.uid) return -1;
          if (b.id == current.uid) return 1;
          return 0;
        });
      }

      if (!mounted) return;
      setState(() {
        _team = users;
        _loadingTeam = false;
      });
    } catch (e) {
      debugPrint('[SettingsScreen] _loadTeam error: $e');
      final current = FirebaseAuth.instance.currentUser;
      List<AppUser> fallback = [];
      if (current != null) {
        final currentRole = AuthService.instance.userRole ?? 'Staff';
        fallback.add(AppUser(
          id: current.uid,
          fullName: AuthService.instance.displayName,
          email: AuthService.instance.email,
          role: currentRole,
        ));
      }
      if (!mounted) return;
      setState(() {
        _team = fallback;
        _loadingTeam = false;
      });
    }
  }
  Future<void> _saveGeneralSettings() async {
    final name = _appNameController.text.trim();
    if (name.isEmpty) {
      NotificationBanner.show(
        context,
        'App name cannot be empty.',
        tone: NotificationTone.warning,
      );
      return;
    }

    await SettingsService.instance.setAppName(name);
    if (!mounted) return;
    NotificationBanner.show(
      context,
      'Workspace preferences saved permanently!',
      tone: NotificationTone.success,
    );
  }

  Future<void> _updateRole(AppUser member, String newRole) async {
    try {
      await AuthService.instance.updateUserRole(member.id, newRole);
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Role updated for ${member.fullName} to $newRole',
        tone: NotificationTone.success,
      );
      _loadTeam();
    } catch (e) {
      debugPrint('[DEBUG] FULL updateUserRole error: $e');
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Failed to update role: $e',
        tone: NotificationTone.error,
      );
    }
  }

  Future<void> _showEditRoleDialog(AppUser member) async {
    String selectedRole = member.role ?? 'Staff';
    final roles = ['Admin', 'Manager', 'Staff'];

    final updatedRole = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            Text('Edit Role for ${member.fullName}', style: AppTextStyles.h3),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select assigned role:', style: AppTextStyles.caption),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    roles.contains(selectedRole) ? selectedRole : 'Staff',
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
                items: roles
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedRole = v);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: AppTextStyles.bodyMedium),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(selectedRole),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Save Role'),
          ),
        ],
      ),
    );

    if (updatedRole != null && updatedRole != member.role) {
      _updateRole(member, updatedRole);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs;
    if (_tab >= tabs.length) {
      _tab = 0;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 600;
    final horizontalPadding = compact ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 28, horizontalPadding, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
              title: 'Settings',
              subtitle: 'Manage your workspace preferences and team.'),
          const SizedBox(height: AppSpacing.lg),
          _buildTabBar(tabs),
          const SizedBox(height: AppSpacing.lg),
          if (_tab == 0) _buildGeneral(),
          if (_tab == 1) _buildNotifications(),
          if (_tab == 2 && AuthService.instance.isAdmin) _buildUserManagement(),
        ],
      ),
    );
  }

  Widget _buildTabBar(List<String> tabs) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < tabs.length; i++)
              GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        _tab == i ? AppColors.primarySoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    tabs[i],
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: _tab == i
                            ? AppColors.primary
                            : AppColors.textSecondary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneral() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('General', style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text('Basic information about your workspace.',
              style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'App Name',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _appNameController,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: 'Enter app name',
              hintStyle:
                  AppTextStyles.body.copyWith(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: PrimaryButton(
              label: 'Save Changes',
              icon: Icons.save_rounded,
              onPressed: _saveGeneralSettings,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifications() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notifications', style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text('Choose what you want to be notified about.',
              style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.lg),
          _toggleRow(
            title: 'Notification Banners (Top-Right Popups)',
            subtitle:
                'Show top-right 2-second overlay banners for actions & alerts.',
            value: _notificationBanner,
            onChanged: (v) async {
              setState(() => _notificationBanner = v);
              await SettingsService.instance.setNotificationBannerEnabled(v);
              if (mounted) {
                NotificationBanner.show(
                  context,
                  v
                      ? 'Notification banners enabled'
                      : 'Notification banners disabled',
                  tone: NotificationTone.info,
                );
              }
            },
          ),
          const Divider(height: AppSpacing.xl),
          _toggleRow(
            title: 'Low Stock Alerts',
            subtitle:
                'Get notified when a product falls below its reorder point (10 units).',
            value: _lowStockAlerts,
            onChanged: (v) async {
              setState(() => _lowStockAlerts = v);
              await SettingsService.instance.setLowStockAlerts(v);
              if (mounted) {
                NotificationBanner.show(
                  context,
                  'Low stock alert preference updated.',
                  tone: NotificationTone.info,
                );
              }
            },
          ),
          const Divider(height: AppSpacing.xl),
          _toggleRow(
            title: 'Inbound Arrival Notices',
            subtitle:
                'Get notified when an inbound stock transaction is completed.',
            value: _inboundNotices,
            onChanged: (v) async {
              setState(() => _inboundNotices = v);
              await SettingsService.instance.setInboundNotices(v);
              if (mounted) {
                NotificationBanner.show(
                  context,
                  'Inbound notices preference updated.',
                  tone: NotificationTone.info,
                );
              }
            },
          ),
          const Divider(height: AppSpacing.xl),
          _toggleRow(
            title: 'Email Summaries',
            subtitle: 'Receive a daily digest of warehouse activity by email.',
            value: _emailSummaries,
            onChanged: (v) async {
              setState(() => _emailSummaries = v);
              await SettingsService.instance.setEmailSummaries(v);
              if (mounted) {
                NotificationBanner.show(
                  context,
                  'Email summaries preference updated.',
                  tone: NotificationTone.info,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(
      {required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 3),
              Text(subtitle, style: AppTextStyles.caption),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.primary,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: AppColors.border,
        ),
      ],
    );
  }

  Widget _buildUserManagement() {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('User Management', style: AppTextStyles.h3),
                    const SizedBox(height: 4),
                    Text(
                        _loadingTeam
                            ? 'Loading team...'
                            : '${_team.length} team member(s) registered.',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              PrimaryButton(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                onPressed: _loadTeam,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loadingTeam)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_team.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Text(
                  'No team members registered yet.',
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ..._team.map((m) => _TeamMemberRow(
                  member: m,
                  onEditRole: () => _showEditRoleDialog(m),
                )),
        ],
      ),
    );
  }
}

class _TeamMemberRow extends StatelessWidget {
  final AppUser member;
  final VoidCallback onEditRole;

  const _TeamMemberRow({
    required this.member,
    required this.onEditRole,
  });

  BadgeTone get _tone {
    switch (member.role?.toLowerCase()) {
      case 'admin':
        return BadgeTone.info;
      case 'manager':
        return BadgeTone.success;
      default:
        return BadgeTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 500;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    member.initials.isNotEmpty ? member.initials : 'U',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(member.fullName,
                      style: AppTextStyles.bodyMedium,
                      overflow: TextOverflow.ellipsis),
                ),
                StatusBadge(label: member.role ?? 'None', tone: _tone),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(member.email,
                      style: AppTextStyles.caption,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  onPressed: onEditRole,
                  icon: const Icon(Icons.manage_accounts_rounded,
                      size: 20, color: AppColors.primary),
                  tooltip: 'Alter Role',
                  splashRadius: 18,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary,
            child: Text(
              member.initials.isNotEmpty ? member.initials : 'U',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.fullName, style: AppTextStyles.bodyMedium),
                Text(member.email, style: AppTextStyles.caption),
              ],
            ),
          ),
          StatusBadge(label: member.role?? 'None', tone: _tone),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onEditRole,
            icon: const Icon(Icons.manage_accounts_rounded,
                size: 20, color: AppColors.primary),
            tooltip: 'Alter Role',
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}