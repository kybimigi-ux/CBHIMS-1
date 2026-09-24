import 'package:flutter/material.dart';
import '../../models/hardware.dart';
import '../../services/auth_service.dart';
import '../../services/hardware_context.dart';
import '../../services/hardware_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/notification_banner.dart';

/// Modal dialog for quickly switching between hardware workspaces without leaving the app layout,
/// or navigating back to the Hardware Lobby.
class SwitchWorkspaceDialog extends StatefulWidget {
  const SwitchWorkspaceDialog({super.key});

  /// Helper to display the switcher dialog.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const SwitchWorkspaceDialog(),
    );
  }

  @override
  State<SwitchWorkspaceDialog> createState() => _SwitchWorkspaceDialogState();
}

class _SwitchWorkspaceDialogState extends State<SwitchWorkspaceDialog> {
  List<Hardware> _hardwares = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadHardwares();
    _searchCtrl.addListener(() {
      if (mounted) {
        setState(() => _query = _searchCtrl.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHardwares() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await HardwareService.instance.getMyHardwares();
      if (mounted) {
        setState(() {
          _hardwares = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<Hardware> get _filtered {
    if (_query.isEmpty) return _hardwares;
    return _hardwares.where((h) {
      final nameMatches = h.name.toLowerCase().contains(_query);
      final descMatches = h.description.toLowerCase().contains(_query);
      return nameMatches || descMatches;
    }).toList();
  }

  void _selectHardware(Hardware hw) {
    final current = HardwareContext.instance.activeHardware;
    if (current?.id == hw.id) {
      Navigator.of(context).pop();
      return;
    }

    HardwareContext.instance.setActiveHardware(hw);
    Navigator.of(context).pop();

    NotificationBanner.show(
      context,
      'Switched workspace to "${hw.name}"',
      tone: NotificationTone.success,
    );
  }

  void _goToLobby() {
    HardwareContext.instance.clearActiveHardware();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _showCreateInlineDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool creating = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
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
          content: SizedBox(
            width: 400,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hardware Name', style: AppTextStyles.label),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'e.g. Downtown Branch',
                      hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.store_rounded, size: 18, color: AppColors.textMuted),
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
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
                  ),
                  const SizedBox(height: 16),
                  Text('Description (optional)', style: AppTextStyles.label),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'e.g. Main storage for plumbing & electrical supplies',
                      hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
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
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: creating ? null : () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: creating
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setS(() => creating = true);
                      try {
                        final hw = await HardwareService.instance.createHardware(
                          name: nameCtrl.text.trim(),
                          description: descCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        // Automatically switch to the newly created hardware
                        _selectHardware(hw);
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Create & Open', style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentHw = HardwareContext.instance.activeHardware;
    final isAdmin = AuthService.instance.isAdmin;
    final screenW = MediaQuery.of(context).size.width;
    final isCompact = screenW < 520;

    return Dialog(
      backgroundColor: AppColors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 40,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Dialog Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Switch Workspace', style: AppTextStyles.h3),
                        const SizedBox(height: 2),
                        Text(
                          'Jump directly to another hardware branch',
                          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                    splashRadius: 20,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // ── Search Field (if more than 3 hardwares or filtering) ──
            if (_hardwares.length > 3 || _query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: TextField(
                  controller: _searchCtrl,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'Filter workspaces...',
                    hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),

            const Divider(height: 16, thickness: 1, color: AppColors.border),

            // ── Hardwares List ──
            Flexible(
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AppColors.danger, size: 36),
                                const SizedBox(height: 8),
                                Text('Failed to load workspaces',
                                    style: AppTextStyles.bodyMedium),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _loadHardwares,
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: const Text('Retry'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _query.isNotEmpty
                                          ? Icons.search_off_rounded
                                          : Icons.storefront_outlined,
                                      size: 40,
                                      color: AppColors.textMuted,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _query.isNotEmpty
                                          ? 'No workspaces matching "$_query"'
                                          : 'No workspaces found',
                                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final hw = _filtered[index];
                                final isActive = hw.id == currentHw?.id;
                                final isCreator = hw.createdBy == AuthService.instance.userId;

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _selectHardware(hw),
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? AppColors.primarySoft.withValues(alpha: 0.5)
                                            : AppColors.background,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isActive
                                              ? AppColors.primary
                                              : AppColors.border,
                                          width: isActive ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: isActive
                                                  ? AppColors.primary
                                                  : AppColors.primarySoft,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              Icons.storefront_rounded,
                                              size: 19,
                                              color: isActive
                                                  ? Colors.white
                                                  : AppColors.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        hw.name,
                                                        style: AppTextStyles.bodyMedium.copyWith(
                                                          fontWeight: FontWeight.w700,
                                                          color: isActive
                                                              ? AppColors.primary
                                                              : AppColors.textPrimary,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (isCreator) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.primary.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          'Owner',
                                                          style: AppTextStyles.caption.copyWith(
                                                            color: AppColors.primary,
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                if (hw.description.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    hw.description,
                                                    style: AppTextStyles.caption.copyWith(
                                                      color: AppColors.textMuted,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.people_outline_rounded,
                                                        size: 12, color: AppColors.textMuted),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${hw.memberIds.length} member${hw.memberIds.length == 1 ? '' : 's'}',
                                                      style: AppTextStyles.caption.copyWith(
                                                        color: AppColors.textMuted,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (isActive)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.check_rounded,
                                                      size: 14, color: Colors.white),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Active',
                                                    style: AppTextStyles.caption.copyWith(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            const Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              size: 14,
                                              color: AppColors.textMuted,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),

            const Divider(height: 16, thickness: 1, color: AppColors.border),

            // ── Dialog Footer Actions ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _goToLobby,
                      icon: const Icon(Icons.grid_view_rounded, size: 16),
                      label: const Text('All Workspaces'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showCreateInlineDialog,
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('New Hardware'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
