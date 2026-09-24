import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notification_banner.dart';
import '../../widgets/section_card.dart';

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

  List<String> get _visibleTabs => const ['General', 'Notifications'];

  @override
  void initState() {
    super.initState();
    final settings = SettingsService.instance;
    _appNameController = TextEditingController(text: settings.appName);
    _notificationBanner = settings.notificationBannerEnabled;
    _lowStockAlerts = settings.lowStockAlerts;
    _inboundNotices = settings.inboundNotices;
    _emailSummaries = settings.emailSummaries;
  }

  @override
  void dispose() {
    _appNameController.dispose();
    super.dispose();
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
              subtitle: 'Manage your workspace preferences.'),
          const SizedBox(height: AppSpacing.lg),
          _buildTabBar(tabs),
          const SizedBox(height: AppSpacing.lg),
          if (_tab == 0) _buildGeneral(),
          if (_tab == 1) _buildNotifications(),
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
}