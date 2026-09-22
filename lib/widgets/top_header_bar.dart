import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class TopHeaderBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onAccountTap;

  const TopHeaderBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.onSearch,
    this.onAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final name = auth.displayName;
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;

      final avatarWidget = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onAccountTap,
          child: CircleAvatar(
            radius: compact ? 16 : 19,
            backgroundColor: AppColors.primary,
            child: Text(
              initials.isNotEmpty ? initials : 'U',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );

      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.h1),
            const SizedBox(height: 6),
            Text(subtitle,
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: _SearchField(onSearch: onSearch)),
                const SizedBox(width: AppSpacing.sm),
                const _NotificationBell(),
                const SizedBox(width: AppSpacing.sm),
                avatarWidget,
              ],
            ),
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.h1),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Flexible(
            fit: FlexFit.loose,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: _SearchField(onSearch: onSearch),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const _NotificationBell(),
          const SizedBox(width: AppSpacing.md),
          avatarWidget,
        ],
      );
    });
  }
}

class _SearchField extends StatefulWidget {
  final ValueChanged<String>? onSearch;
  const _SearchField({this.onSearch});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: widget.onSearch,
                onSubmitted: widget.onSearch,
                style: AppTextStyles.body,
                decoration: InputDecoration.collapsed(
                  hintText: 'Search products...',
                  hintStyle:
                      AppTextStyles.body.copyWith(color: AppColors.textMuted),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _controller.clear();
                  widget.onSearch?.call('');
                  setState(() {});
                },
                child: const Icon(Icons.close_rounded,
                    size: 16, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Notifications',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 48),
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notifications', style: AppTextStyles.h3.copyWith(fontSize: 15)),
              const SizedBox(height: 4),
              Text('Recent system activities & alerts', style: AppTextStyles.caption),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'low_stock',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.warningSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppColors.warning),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Low Stock Alert', style: AppTextStyles.bodyMedium),
                    Text('Check products below 10 units',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'system',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline_rounded,
                    size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('System Ready', style: AppTextStyles.bodyMedium),
                    Text('STOKADO connected to Firebase',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications_none_rounded,
                size: 20, color: AppColors.textSecondary),
            Positioned(
              top: 10,
              right: 11,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: AppColors.danger, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
