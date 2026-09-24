import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notification_banner.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_badge.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _savingProfile = false;
  bool _savingPassword = false;
  String? _role;

  @override
  void initState() {
    super.initState();
    _nameController.text = AuthService.instance.displayName;
    _role = AuthService.instance.userRole;
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await AuthService.instance.fetchUserRole();
    if (mounted) {
      setState(() => _role = role);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      NotificationBanner.show(
        context,
        'Please enter a valid full name.',
        tone: NotificationTone.warning,
      );
      return;
    }

    setState(() => _savingProfile = true);
    try {
      await AuthService.instance.updateProfile(fullName: newName);
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Profile updated successfully!',
        tone: NotificationTone.success,
      );
    } catch (e) {
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Failed to update profile: $e',
        tone: NotificationTone.error,
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _updatePassword() async {
    final pwd = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (pwd.length < 6) {
      NotificationBanner.show(
        context,
        'Password must be at least 6 characters long.',
        tone: NotificationTone.warning,
      );
      return;
    }

    if (pwd != confirm) {
      NotificationBanner.show(
        context,
        'Passwords do not match.',
        tone: NotificationTone.warning,
      );
      return;
    }

    setState(() => _savingPassword = true);
    try {
      await AuthService.instance.updatePassword(pwd);
      if (!mounted) return;
      _passwordController.clear();
      _confirmPasswordController.clear();
      NotificationBanner.show(
        context,
        'Password updated successfully!',
        tone: NotificationTone.success,
      );
    } catch (e) {
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Failed to update password: $e',
        tone: NotificationTone.error,
      );
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: AppColors.danger, size: 22),
            const SizedBox(width: 10),
            Text('Log Out', style: AppTextStyles.h3),
          ],
        ),
        content: Text(
          'Are you sure you want to log out of STOKADO?',
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
  }

  BadgeTone get _roleBadgeTone {
    switch ((_role ?? '').toLowerCase()) {
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
    final auth = AuthService.instance;
    final name = auth.displayName;
    final email = auth.email;

    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 600;
    final horizontalPadding = compact ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 28, horizontalPadding, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            title: 'Account Settings',
            subtitle: 'Manage your profile details and security options.',
          ),
          const SizedBox(height: AppSpacing.lg),

          // User Header Card
          SectionCard(
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.primary,
                            child: Text(
                              initials.isNotEmpty ? initials : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: AppTextStyles.h3),
                                const SizedBox(height: 2),
                                if (_role != null)
                                  StatusBadge(label: _role!, tone: _roleBadgeTone),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(email, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: SecondaryButton(
                          label: 'Logout',
                          icon: Icons.logout_rounded,
                          onPressed: _handleLogout,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          initials.isNotEmpty ? initials : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: AppTextStyles.h2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (_role != null)
                                  StatusBadge(label: _role!, tone: _roleBadgeTone)
                                else
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(email, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      SecondaryButton(
                        label: 'Logout',
                        icon: Icons.logout_rounded,
                        onPressed: _handleLogout,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Edit Profile Card
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Personal Information', style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text('Update your display name.', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.lg),
                Text('Full Name', style: AppTextStyles.label),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'Enter full name',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: _savingProfile ? 'Saving...' : 'Save Profile',
                  icon: Icons.check_rounded,
                  onPressed: _savingProfile ? null : _updateProfile,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Change Password Card
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Security', style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text('Change your account password.', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.lg),
                Text('New Password', style: AppTextStyles.label),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'At least 6 characters',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Confirm New Password', style: AppTextStyles.label),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'Re-enter new password',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: _savingPassword ? 'Updating...' : 'Change Password',
                  icon: Icons.lock_reset_rounded,
                  onPressed: _savingPassword ? null : _updatePassword,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}