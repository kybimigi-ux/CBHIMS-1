import 'package:flutter/material.dart';
import '../models/hardware.dart';
import '../services/auth_service.dart';
import '../services/hardware_context.dart';
import '../services/hardware_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_banner.dart';
import 'hardware_settings_screen.dart';
import 'main_layout_screen.dart';

/// The workspace lobby — shown after login.
/// Admins see workspaces they created; Staff see workspaces they were invited to.
class HardwareLobbyScreen extends StatefulWidget {
  const HardwareLobbyScreen({super.key});

  @override
  State<HardwareLobbyScreen> createState() => _HardwareLobbyScreenState();
}

class _HardwareLobbyScreenState extends State<HardwareLobbyScreen>
    with SingleTickerProviderStateMixin {
  List<Hardware> _hardwares = [];
  bool _loading = true;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadHardwares();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHardwares() async {
    setState(() => _loading = true);
    try {
      final list = await HardwareService.instance.getMyHardwares();
      if (mounted) {
        setState(() {
          _hardwares = list;
          _loading = false;
        });
        _fadeCtrl.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        NotificationBanner.show(context, 'Failed to load workspaces: $e',
            tone: NotificationTone.error);
      }
    }
  }

  void _openHardware(Hardware hw) {
    HardwareContext.instance.setActiveHardware(hw);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MainLayoutScreen()))
        .then((_) {
      // Reload the list whenever we return from inside a workspace
      // (handles delete, leave-workspace, etc. without the user needing
      // to manually refresh).
      if (mounted) _loadHardwares();
    });
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool creating = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text('Create Hardware', style: AppTextStyles.h3),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Hardware Name', style: AppTextStyles.label),
                const SizedBox(height: 8),
                TextFormField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: AppTextStyles.body,
                  decoration: _inputDec(
                      hint: 'e.g. Main Branch, Warehouse A', icon: Icons.business_outlined),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                Text('Description (optional)', style: AppTextStyles.label),
                const SizedBox(height: 8),
                TextFormField(
                  controller: descCtrl,
                  style: AppTextStyles.body,
                  maxLines: 2,
                  decoration: _inputDec(
                      hint: 'Short description of this hardware store', icon: Icons.notes_rounded),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: creating ? null : () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: AppTextStyles.bodyMedium),
            ),
            ElevatedButton(
              onPressed: creating
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setS(() => creating = true);
                      try {
                        final hw = await HardwareService.instance.createHardware(
                          name: nameCtrl.text,
                          description: descCtrl.text,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          await _loadHardwares();
                          _openHardware(hw);
                        }
                      } catch (e) {
                        setS(() => creating = false);
                        if (ctx.mounted) {
                          NotificationBanner.show(ctx, 'Failed to create: $e',
                              tone: NotificationTone.error);
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    descCtrl.dispose();
  }

  InputDecoration _inputDec({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
      prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final isAdmin = auth.isAdmin;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Hero App Bar ──
          SliverAppBar(
            expandedHeight: compact ? 160 : 200,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.8),
                      const Color(0xFF1A56DB),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(compact ? 20 : 32, 20, compact ? 20 : 32, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.storefront_rounded,
                                  color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 10),
                            Text('STOKADO',
                                style: AppTextStyles.h3
                                    .copyWith(color: Colors.white)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isAdmin
                              ? 'Your Hardware Workspaces'
                              : 'Your Assigned Workspaces',
                          style: AppTextStyles.h2
                              .copyWith(color: Colors.white, fontSize: compact ? 20 : 24),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAdmin
                              ? 'Select a workspace to manage inventory and transactions.'
                              : 'Select a workspace to view inventory and transactions.',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                icon:
                    const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
                onPressed: _loadHardwares,
              ),
              IconButton(
                tooltip: 'Sign Out',
                icon:
                    const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
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
              const SizedBox(width: 4),
            ],
          ),

          // ── Content ──
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                compact ? 16 : 32, 24, compact ? 16 : 32, 40),
            sliver: _loading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()))
                : _hardwares.isEmpty
                    ? SliverFillRemaining(
                        child: _buildEmptyState(isAdmin, compact))
                    : SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 360,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          mainAxisExtent: 190,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => FadeTransition(
                            opacity: _fadeAnim,
                            child: _HardwareCard(
                              hardware: _hardwares[i],
                              isCurrentUserAdmin: isAdmin,
                              onTap: () => _openHardware(_hardwares[i]),
                              onSettings: isAdmin
                                  ? () => _openSettings(_hardwares[i])
                                  : null,
                            ),
                          ),
                          childCount: _hardwares.length,
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_rounded),
              label: Text('New Hardware', style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
            )
          : null,
    );
  }

  Widget _buildEmptyState(bool isAdmin, bool compact) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.storefront_outlined,
                size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text(
            isAdmin ? 'No Hardware Yet' : 'No Workspaces Found',
            style: AppTextStyles.h3,
          ),
          const SizedBox(height: 8),
          Text(
            isAdmin
                ? 'Create your first hardware workspace\nto start managing inventory.'
                : 'You haven\'t been invited to any workspace.\nContact your admin with your email:',
            style: AppTextStyles.body
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (!isAdmin) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                AuthService.instance.email,
                style: AppTextStyles.mono
                    .copyWith(color: AppColors.primary, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 28),
          if (isAdmin)
            ElevatedButton.icon(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create Hardware'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _loadHardwares,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }

  void _openSettings(Hardware hw) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HardwareSettingsScreen(hardware: hw)),
    );
    _loadHardwares();
  }
}

// ---------------------------------------------------------------------------
// Hardware Card Widget
// ---------------------------------------------------------------------------

class _HardwareCard extends StatelessWidget {
  final Hardware hardware;
  final bool isCurrentUserAdmin;
  final VoidCallback onTap;
  final VoidCallback? onSettings;

  const _HardwareCard({
    required this.hardware,
    required this.isCurrentUserAdmin,
    required this.onTap,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final hue = hardware.name.hashCode % 360;
    final cardColor = HSLColor.fromAHSL(1.0, hue.toDouble().abs() % 360, 0.65, 0.45).toColor();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              hoverColor: AppColors.primary.withValues(alpha: 0.04),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon + settings
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: cardColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.storefront_rounded,
                              color: cardColor, size: 24),
                        ),
                        const Spacer(),
                        if (onSettings != null)
                          IconButton(
                            onPressed: onSettings,
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            color: AppColors.textMuted,
                            tooltip: 'Hardware Settings',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Name
                    Text(
                      hardware.name,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hardware.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        hardware.description,
                        style: AppTextStyles.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    // Footer
                    Row(
                      children: [
                        const Icon(Icons.people_outline_rounded,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          '${hardware.memberCount} member${hardware.memberCount != 1 ? 's' : ''}',
                          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Open →',
                            style: AppTextStyles.label.copyWith(
                                color: AppColors.primary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
