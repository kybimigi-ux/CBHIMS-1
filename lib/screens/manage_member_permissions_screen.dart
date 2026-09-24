import 'package:flutter/material.dart';
import '../models/hardware.dart';
import '../services/hardware_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_banner.dart';

/// Screen allowing Store Owners/Admins to manage granular permissions
/// for staff members in a specific hardware workspace.
class ManageMemberPermissionsScreen extends StatefulWidget {
  final Hardware hardware;
  const ManageMemberPermissionsScreen({super.key, required this.hardware});

  @override
  State<ManageMemberPermissionsScreen> createState() =>
      _ManageMemberPermissionsScreenState();
}

class _ManageMemberPermissionsScreenState
    extends State<ManageMemberPermissionsScreen> {
  late Hardware _hw;
  bool _loading = false;

  // Track editable permissions locally per member userId
  final Map<String, MemberPermissions> _localPermissions = {};
  final Set<String> _savingUsers = {};

  @override
  void initState() {
    super.initState();
    _hw = widget.hardware;
    _initPermissions();
  }

  void _initPermissions() {
    _localPermissions.clear();
    for (final member in _hw.members.values) {
      if (!member.isAdmin && member.userId != _hw.createdBy) {
        _localPermissions[member.userId] = member.permissions;
      }
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final fresh = await HardwareService.instance.getById(_hw.id);
    if (mounted && fresh != null) {
      setState(() {
        _hw = fresh;
        _initPermissions();
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveMemberPermissions(
      String userId, MemberPermissions permissions, String memberName) async {
    setState(() => _savingUsers.add(userId));
    try {
      await HardwareService.instance
          .updateMemberPermissions(_hw.id, userId, permissions);
      if (mounted) {
        NotificationBanner.show(
          context,
          'Updated permissions for $memberName',
          tone: NotificationTone.success,
        );
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        NotificationBanner.show(
          context,
          'Failed to update permissions: $e',
          tone: NotificationTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingUsers.remove(userId));
      }
    }
  }

  void _updatePermissionLocal(
    String userId,
    MemberPermissions Function(MemberPermissions current) updateFn,
  ) {
    setState(() {
      final current = _localPermissions[userId] ?? const MemberPermissions();
      _localPermissions[userId] = updateFn(current);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 700;
    final hPad = compact ? 16.0 : 32.0;

    // Staff members only (excluding admins and store owner/creator)
    final staffMembers = _hw.memberList
        .where((m) => !m.isAdmin && m.userId != _hw.createdBy)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Manage Permissions',
                style: AppTextStyles.h3,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _hw.name,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.primary, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 60),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Overview Banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.admin_panel_settings_outlined,
                                color: AppColors.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Staff Access Control',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Configure permissions for staff members in this workspace. Admins and store owners automatically have full permissions.',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Member List or Empty State
                      if (staffMembers.isEmpty)
                        _buildEmptyStaffState()
                      else
                        ...staffMembers.map((member) => _buildMemberCard(member)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyStaffState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.neutralSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline_rounded,
              size: 28,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Staff Members to Manage',
            style: AppTextStyles.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'All members in this workspace are Store Owners or Admins. '
              'Invite staff members in Workspace Settings to customize their product and transaction access.',
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary, fontSize: 13.5),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back to Settings'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(HardwareMember member) {
    final permissions =
        _localPermissions[member.userId] ?? member.permissions;
    final isSaving = _savingUsers.contains(member.userId);

    final allProductsEnabled = permissions.canAddProducts &&
        permissions.canEditProducts &&
        permissions.canRemoveProducts;

    final allTransactionsEnabled =
        permissions.canAddTransactions && permissions.canCancelTransactions;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Member Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primarySoft,
                      child: Text(
                        member.initials,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
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
                              Flexible(
                                child: Text(
                                  member.fullName,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.neutralSoft,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Staff',
                                  style: AppTextStyles.label.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            member.email,
                            style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Save button — always fixed width so it never overflows
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () => _saveMemberPermissions(
                                  member.userId,
                                  permissions,
                                  member.fullName,
                                ),
                        icon: isSaving
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 15),
                        label: Text(
                          isSaving ? 'Saving…' : 'Save',
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // Permissions Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Products Permissions ──
                Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 17,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Product Permissions',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final nextVal = !allProductsEnabled;
                        _updatePermissionLocal(
                          member.userId,
                          (c) => c.copyWith(
                            canAddProducts: nextVal,
                            canEditProducts: nextVal,
                            canRemoveProducts: nextVal,
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        allProductsEnabled ? 'Revoke All' : 'Allow All',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildCheckboxTile(
                        title: 'Allow to Add Products',
                        subtitle: 'Can create new items in the inventory catalog',
                        value: permissions.canAddProducts,
                        onChanged: (val) {
                          _updatePermissionLocal(
                            member.userId,
                            (c) => c.copyWith(canAddProducts: val ?? false),
                          );
                        },
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _buildCheckboxTile(
                        title: 'Allow to Edit Products',
                        subtitle:
                            'Can modify details, names, prices and categories',
                        value: permissions.canEditProducts,
                        onChanged: (val) {
                          _updatePermissionLocal(
                            member.userId,
                            (c) => c.copyWith(canEditProducts: val ?? false),
                          );
                        },
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _buildCheckboxTile(
                        title: 'Allow to Remove Products',
                        subtitle:
                            'Can archive and delete products from this store',
                        value: permissions.canRemoveProducts,
                        onChanged: (val) {
                          _updatePermissionLocal(
                            member.userId,
                            (c) => c.copyWith(canRemoveProducts: val ?? false),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Transactions Permissions ──
                Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 17,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Transaction Permissions',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final nextVal = !allTransactionsEnabled;
                        _updatePermissionLocal(
                          member.userId,
                          (c) => c.copyWith(
                            canAddTransactions: nextVal,
                            canCancelTransactions: nextVal,
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        allTransactionsEnabled ? 'Revoke All' : 'Allow All',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildCheckboxTile(
                        title: 'Allow to Add Transactions',
                        subtitle:
                            'Can record Inbound (Receive) and Outbound (Release) movements',
                        value: permissions.canAddTransactions,
                        onChanged: (val) {
                          _updatePermissionLocal(
                            member.userId,
                            (c) => c.copyWith(canAddTransactions: val ?? false),
                          );
                        },
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      _buildCheckboxTile(
                        title: 'Allow to Cancel Transactions',
                        subtitle:
                            'Can void and delete transactions, automatically reversing stock',
                        value: permissions.canCancelTransactions,
                        onChanged: (val) {
                          _updatePermissionLocal(
                            member.userId,
                            (c) =>
                                c.copyWith(canCancelTransactions: val ?? false),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primary,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      title: Text(
        title,
        style: AppTextStyles.bodyMedium.copyWith(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
