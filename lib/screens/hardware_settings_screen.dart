import 'package:flutter/material.dart';
import '../models/hardware.dart';
import '../services/auth_service.dart';
import '../services/hardware_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_banner.dart';

/// Settings screen for a hardware workspace — lets admins manage members,
/// invite staff by email, rename/describe the workspace, and delete it.
class HardwareSettingsScreen extends StatefulWidget {
  final Hardware hardware;
  const HardwareSettingsScreen({super.key, required this.hardware});

  @override
  State<HardwareSettingsScreen> createState() => _HardwareSettingsScreenState();
}

class _HardwareSettingsScreenState extends State<HardwareSettingsScreen> {
  late Hardware _hw;
  bool _loading = false;
  bool _saving = false;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  final TextEditingController _inviteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hw = widget.hardware;
    _nameCtrl = TextEditingController(text: _hw.name);
    _descCtrl = TextEditingController(text: _hw.description);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _inviteCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final fresh = await HardwareService.instance.getById(_hw.id);
    if (mounted && fresh != null) {
      setState(() { _hw = fresh; _loading = false; });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveInfo() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      NotificationBanner.show(context, 'Hardware name cannot be empty.',
          tone: NotificationTone.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      await HardwareService.instance.updateHardware(_hw.id,
          name: name, description: _descCtrl.text.trim());
      await _reload();
      if (mounted) {
        NotificationBanner.show(context, 'Workspace updated.',
            tone: NotificationTone.success);
      }
    } catch (e) {
      if (mounted) {
        NotificationBanner.show(context, 'Failed to save: $e',
            tone: NotificationTone.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendInvite() async {
    final email = _inviteCtrl.text.trim().toLowerCase();
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      NotificationBanner.show(context, 'Enter a valid email address.',
          tone: NotificationTone.warning);
      return;
    }
    if (_hw.invitedEmails.contains(email)) {
      NotificationBanner.show(context, '$email is already invited.',
          tone: NotificationTone.warning);
      return;
    }
    try {
      await HardwareService.instance.inviteMemberByEmail(_hw.id, email);
      _inviteCtrl.clear();
      await _reload();
      if (mounted) {
        NotificationBanner.show(context, 'Invited $email.',
            tone: NotificationTone.success);
      }
    } catch (e) {
      if (mounted) {
        NotificationBanner.show(context, 'Failed to invite: $e',
            tone: NotificationTone.error);
      }
    }
  }

  Future<void> _removeMember(String userId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove $name?', style: AppTextStyles.h3),
        content: Text('This will remove them from the workspace.',
            style: AppTextStyles.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: AppTextStyles.bodyMedium)),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger, foregroundColor: Colors.white, elevation: 0),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await HardwareService.instance.removeMember(_hw.id, userId);
      await _reload();
      if (mounted) {
        NotificationBanner.show(context, '$name removed.',
            tone: NotificationTone.success);
      }
    } catch (e) {
      if (mounted) {
        NotificationBanner.show(context, 'Failed: $e',
            tone: NotificationTone.error);
      }
    }
  }

  Future<void> _removeInvite(String email) async {
    try {
      await HardwareService.instance.removeInvite(_hw.id, email);
      await _reload();
      if (mounted) {
        NotificationBanner.show(context, 'Invite removed.',
            tone: NotificationTone.success);
      }
    } catch (e) {
      if (mounted) {
        NotificationBanner.show(context, 'Failed: $e',
            tone: NotificationTone.error);
      }
    }
  }

  Future<void> _deleteHardware() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete "${_hw.name}"?', style: AppTextStyles.h3),
        content: Text(
            'This will permanently delete this workspace. Inventory and transaction data will remain but unlinked.',
            style: AppTextStyles.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: AppTextStyles.bodyMedium)),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger, foregroundColor: Colors.white, elevation: 0),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await HardwareService.instance.deleteHardware(_hw.id);
      if (mounted) { Navigator.of(context).pop(); }
    } catch (e) {
      if (mounted) {
        NotificationBanner.show(context, 'Failed: $e',
            tone: NotificationTone.error);
      }
    }
  }

  InputDecoration _inputDec(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
        prefixIcon: icon != null ? Icon(icon, size: 18, color: AppColors.textMuted) : null,
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
      );

  @override
  Widget build(BuildContext context) {
    final currentUid = AuthService.instance.userId;
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 700;
    final hPad = compact ? 16.0 : 32.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hardware Settings', style: AppTextStyles.h3),
            Text(_hw.name,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.primary, fontSize: 12)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section: Workspace Info ──
                  _buildSectionHeader('Workspace Info',
                      Icons.business_outlined, 'Edit the name and description.'),
                  const SizedBox(height: 14),
                  _buildCard(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hardware Name', style: AppTextStyles.label),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameCtrl,
                        style: AppTextStyles.body,
                        decoration: _inputDec('Hardware name', icon: Icons.business_outlined),
                      ),
                      const SizedBox(height: 16),
                      Text('Description', style: AppTextStyles.label),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descCtrl,
                        style: AppTextStyles.body,
                        maxLines: 2,
                        decoration: _inputDec('Optional description', icon: Icons.notes_rounded),
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _saveInfo,
                          icon: _saving
                              ? const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                              : const Icon(Icons.save_rounded, size: 16),
                          label: Text(_saving ? 'Saving…' : 'Save Changes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  )),

                  const SizedBox(height: 28),

                  // ── Section: Invite Staff ──
                  _buildSectionHeader(
                      'Invite Staff', Icons.person_add_outlined, 'Staff are notified on their next login.'),
                  const SizedBox(height: 14),
                  _buildCard(Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inviteCtrl,
                          style: AppTextStyles.body,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _inputDec('staff@example.com', icon: Icons.email_outlined),
                          onSubmitted: (_) => _sendInvite(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _sendInvite,
                        icon: const Icon(Icons.send_rounded, size: 15),
                        label: const Text('Invite'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  )),

                  // ── Pending Invites ──
                  if (_hw.invitedEmails.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildCard(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text('Pending Invites', style: AppTextStyles.label),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._hw.invitedEmails.map((email) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 32, height: 32,
                                decoration: const BoxDecoration(
                                  color: AppColors.warningSoft,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.hourglass_top_rounded,
                                    size: 16, color: AppColors.textSecondary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(email, style: AppTextStyles.body)),
                              IconButton(
                                onPressed: () => _removeInvite(email),
                                icon: const Icon(Icons.close_rounded, size: 16),
                                color: AppColors.textMuted,
                                tooltip: 'Remove Invite',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        )),
                      ],
                    )),
                  ],

                  const SizedBox(height: 28),

                  // ── Section: Members ──
                  _buildSectionHeader(
                      'Members', Icons.people_outlined,
                      '${_hw.memberCount} member${_hw.memberCount != 1 ? 's' : ''} in this workspace.'),
                  const SizedBox(height: 14),
                  _buildCard(Column(
                    children: _hw.memberList.map((member) {
                      final isCurrentUser = member.userId == currentUid;
                      final isCreator = member.userId == _hw.createdBy;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: member.isAdmin
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : AppColors.neutralSoft,
                              child: Text(
                                member.initials,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: member.isAdmin
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        isCurrentUser ? '${member.fullName} (You)' : member.fullName,
                                        style: AppTextStyles.bodyMedium.copyWith(fontSize: 13.5),
                                      ),
                                      if (isCreator) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.primarySoft,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('Owner',
                                              style: AppTextStyles.label.copyWith(
                                                  color: AppColors.primary, fontSize: 10)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(member.email,
                                      style: AppTextStyles.caption.copyWith(fontSize: 11.5)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: member.isAdmin ? AppColors.primarySoft : AppColors.neutralSoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                member.isAdmin ? 'Admin' : 'Staff',
                                style: AppTextStyles.label.copyWith(
                                  color: member.isAdmin ? AppColors.primary : AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (!isCurrentUser && !isCreator) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () => _removeMember(member.userId, member.fullName),
                                icon: const Icon(Icons.person_remove_outlined, size: 16),
                                color: AppColors.danger.withValues(alpha: 0.7),
                                tooltip: 'Remove Member',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  )),

                  const SizedBox(height: 40),

                  // ── Danger Zone ──
                  if (_hw.createdBy == currentUid) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.dangerSoft,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 18, color: AppColors.danger),
                              const SizedBox(width: 8),
                              Text('Danger Zone',
                                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.danger)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Permanently delete this workspace. This action cannot be undone.',
                            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _deleteHardware,
                            icon: const Icon(Icons.delete_forever_outlined, size: 16),
                            label: Text('Delete "${_hw.name}"'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, String subtitle) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.primarySoft, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.bodyMedium),
              Text(subtitle, style: AppTextStyles.caption.copyWith(fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}
