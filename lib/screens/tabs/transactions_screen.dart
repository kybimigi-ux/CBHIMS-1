import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/transaction.dart';
import '../../services/auth_service.dart';
import '../../services/hardware_context.dart';
import '../../services/connectivity_service.dart';
import '../../services/offline_queue_service.dart';
import '../../services/sync_service.dart';
import '../../services/transaction_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/notification_banner.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_badge.dart';
import '../dialogs_screen/add_transaction_screen.dart';
import '../transaction_receipt_screen.dart';

enum TransactionTypeFilter { all, receive, release }

extension _TransactionTypeFilterLabel on TransactionTypeFilter {
  String get label {
    switch (this) {
      case TransactionTypeFilter.all:
        return 'All Types';
      case TransactionTypeFilter.receive:
        return 'Receive';
      case TransactionTypeFilter.release:
        return 'Release';
    }
  }
}

enum TransactionSort { recentlyAdded, oldestFirst }

extension _TransactionSortLabel on TransactionSort {
  String get label {
    switch (this) {
      case TransactionSort.recentlyAdded:
        return 'Recently Added';
      case TransactionSort.oldestFirst:
        return 'Oldest First';
    }
  }
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Transaction> _transactions = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<bool>? _syncSubscription;

  TransactionTypeFilter _typeFilter = TransactionTypeFilter.all;
  TransactionSort _sortOption = TransactionSort.recentlyAdded;

  bool get _canCancelTransactions =>
      HardwareContext.instance.canCancelTransactions;
  bool get _canAddTransactions => HardwareContext.instance.canAddTransactions;

  int get _pendingSyncCount =>
      _transactions.where((t) => t.isPendingSync).length;

  @override
  void initState() {
    super.initState();
    _loadTransactions();

    _syncSubscription = ConnectivityService.instance.onOnlineStatusChanged
        .listen((isOnline) async {
      if (isOnline) {
        await SyncService.instance.syncPendingTransactions();
        if (mounted) _loadTransactions();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final txns = await TransactionService.instance.getAll();

      final pendingLocal = OfflineQueueService.instance.getAll().map((p) {
        return Transaction(
          billNo: p.billNo,
          type: p.type,
          totalItems:
              p.items.fold<double>(0.0, (sum, item) => sum + item.quantity),
          remarks: p.remarks,
          createdBy: p.userId,
          createdAt: p.queuedAt,
          items: p.items,
          localId: p.localId,
          isPendingSync: true,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _transactions = [...pendingLocal, ...txns];
        _loading = false;
      });

      if (pendingLocal.isNotEmpty) {
        NotificationBanner.show(
          context,
          '${pendingLocal.length} transaction'
          '${pendingLocal.length == 1 ? '' : 's'} waiting to sync — '
          'look for the "Pending Sync" badge below.',
          tone: NotificationTone.warning,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Transaction> get _filteredTransactions {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _transactions.where((t) {
      final matchesQuery =
          query.isEmpty || t.billNo.toLowerCase().contains(query);

      final matchesType = switch (_typeFilter) {
        TransactionTypeFilter.all => true,
        TransactionTypeFilter.receive => t.type.toLowerCase() == 'receive' ||
            t.type.toLowerCase() == 'inbound',
        TransactionTypeFilter.release => t.type.toLowerCase() == 'release' ||
            t.type.toLowerCase() == 'outbound',
      };

      return matchesQuery && matchesType;
    }).toList();

    switch (_sortOption) {
      case TransactionSort.recentlyAdded:
        filtered.sort((a, b) {
          // Pending items always at top for recently added
          if (a.isPendingSync && !b.isPendingSync) return -1;
          if (!a.isPendingSync && b.isPendingSync) return 1;

          final dateA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateComp = dateB.compareTo(dateA);
          if (dateComp != 0) return dateComp;
          return (b.id ?? '').compareTo(a.id ?? '');
        });
        break;
      case TransactionSort.oldestFirst:
        filtered.sort((a, b) {
          final dateA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateComp = dateA.compareTo(dateB);
          if (dateComp != 0) return dateComp;
          return (a.id ?? '').compareTo(b.id ?? '');
        });
        break;
    }

    return filtered;
  }

  Future<void> _onReceive() async {
    final added =
        await AddTransactionScreen.show(context, initialType: 'Receive');
    if (added == true) {
      _loadTransactions();
    }
  }

  Future<void> _onRelease() async {
    final added =
        await AddTransactionScreen.show(context, initialType: 'Release');
    if (added == true) {
      _loadTransactions();
    }
  }

  Future<void> _onDeleteTransaction(Transaction txn) async {
    if (txn.isPendingSync) {
      if (txn.localId != null) {
        await OfflineQueueService.instance.remove(txn.localId!);
        if (!mounted) return;
        NotificationBanner.show(
          context,
          'Removed unsynced transaction ${txn.billNo} from the queue.',
          tone: NotificationTone.success,
        );
        _loadTransactions();
      }
      return;
    }
    if (txn.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            Text('Delete Transaction ${txn.billNo}?', style: AppTextStyles.h3),
        content: Text(
          'This will permanently delete this transaction and its items, '
          'and automatically reverse the stock quantities back to inventory.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep Transaction', style: AppTextStyles.bodyMedium),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TransactionService.instance.deleteTransaction(txn.id!);
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Transaction ${txn.billNo} deleted.',
        tone: NotificationTone.success,
      );
      _loadTransactions();
    } catch (e) {
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Failed to delete transaction: $e',
        tone: NotificationTone.error,
      );
    }
  }

  Future<void> _showTransactionDetails(Transaction txn) async {
    if (txn.isPendingSync) {
      NotificationBanner.show(
        context,
        'This transaction is still queued offline — details will be available once it syncs.',
        tone: NotificationTone.warning,
      );
      return;
    }
    try {
      final detailedTxn = txn.id != null
          ? await TransactionService.instance.getById(txn.id!)
          : txn;
      if (!mounted) return;
      await TransactionReceiptScreen.navigateTo(context, detailedTxn);
      if (mounted) {
        _loadTransactions();
      }
    } catch (e) {
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Failed to load transaction details: $e',
        tone: NotificationTone.error,
      );
    }
  }

  String _getCreatedByName(Transaction t) {
    if (t.createdByName != null &&
        t.createdByName!.trim().isNotEmpty &&
        t.createdByName!.trim().toLowerCase() != 'user' &&
        t.createdByName!.trim().toLowerCase() != 'system user') {
      return t.createdByName!.trim();
    }
    if (t.createdBy != null &&
        t.createdBy!.trim().isNotEmpty &&
        !t.createdBy!.contains('-')) {
      return t.createdBy!.trim();
    }
    final authDisplayName = AuthService.instance.displayName.trim();
    if (authDisplayName.isNotEmpty && authDisplayName.toLowerCase() != 'user') {
      return authDisplayName;
    }
    final authEmail = AuthService.instance.email.trim();
    if (authEmail.isNotEmpty) {
      final emailPrefix = authEmail.split('@').first;
      if (emailPrefix.isNotEmpty && emailPrefix.toLowerCase() != 'user') {
        return emailPrefix;
      }
    }
    final authRole = AuthService.instance.userRole?.trim();
    if (authRole != null && authRole.isNotEmpty) {
      return authRole;
    }
    return 'Admin';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTransactions;
    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 600;
    final horizontalPadding = compact ? 16.0 : 32.0;

    String subtitleText;
    if (_loading) {
      subtitleText = 'Loading transactions...';
    } else if (filtered.length != _transactions.length) {
      subtitleText =
          '${filtered.length} of ${_transactions.length} transactions';
      if (_pendingSyncCount > 0) {
        subtitleText += ' · $_pendingSyncCount pending sync';
      }
    } else {
      subtitleText = _pendingSyncCount > 0
          ? '${_transactions.length} total stock transactions · $_pendingSyncCount pending sync'
          : '${_transactions.length} total stock transactions';
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                horizontalPadding, 28, horizontalPadding, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScreenHeader(
                  title: 'Transactions',
                  subtitle: subtitleText,
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildFilterBar(),
                const SizedBox(height: AppSpacing.lg),
                SectionCard(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                  child: _loading
                      ? const SizedBox(
                          height: 240,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _error != null
                          ? SizedBox(
                              height: 200,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Failed to load transactions',
                                        style: AppTextStyles.h3),
                                    const SizedBox(height: 8),
                                    Text(_error!,
                                        style: AppTextStyles.caption
                                            .copyWith(color: AppColors.danger)),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: _loadTransactions,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : filtered.isEmpty
                              ? SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: Text(
                                      _transactions.isEmpty
                                          ? 'No transactions recorded yet. Click "Receive" or "Release" to create one.'
                                          : 'No transactions match your search or filter criteria.',
                                      style: AppTextStyles.body.copyWith(
                                          color: AppColors.textSecondary),
                                    ),
                                  ),
                                )
                              : compact
                                  ? _buildMobileTransactionList(filtered)
                                  : _buildDesktopTransactionTable(filtered),
                ),
              ],
            ),
          ),
        ),
        if (_canAddTransactions)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border(top: BorderSide(color: AppColors.border)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _onReceive,
                      icon: const Icon(Icons.call_received_rounded,
                          color: Colors.white, size: 20),
                      label: Text(
                        'Receive',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: Colors.white, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _onRelease,
                      icon: const Icon(Icons.arrow_upward_rounded,
                          color: Colors.white, size: 20),
                      label: Text(
                        'Release',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: Colors.white, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final compact = MediaQuery.of(context).size.width < 600;

    final searchField = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration.collapsed(
                hintText: 'Search bill number...',
                hintStyle:
                    AppTextStyles.body.copyWith(color: AppColors.textMuted),
              ),
              style: AppTextStyles.body,
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() {});
              },
              child: const Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textMuted),
            ),
        ],
      ),
    );

    final typeDropdown = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TransactionTypeFilter>(
          value: _typeFilter,
          icon: const Icon(Icons.filter_list_rounded,
              size: 18, color: AppColors.textSecondary),
          style: AppTextStyles.body,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          isExpanded: compact,
          items: TransactionTypeFilter.values
              .map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(f.label),
                  ))
              .toList(),
          onChanged: (v) =>
              setState(() => _typeFilter = v ?? TransactionTypeFilter.all),
        ),
      ),
    );

    final sortDropdown = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TransactionSort>(
          value: _sortOption,
          icon: const Icon(Icons.swap_vert_rounded,
              size: 18, color: AppColors.textSecondary),
          style: AppTextStyles.body,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          isExpanded: compact,
          items: TransactionSort.values
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.label),
                  ))
              .toList(),
          onChanged: (v) =>
              setState(() => _sortOption = v ?? TransactionSort.recentlyAdded),
        ),
      ),
    );

    if (compact) {
      return Column(
        children: [
          searchField,
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: typeDropdown),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: sortDropdown),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: AppSpacing.md),
        typeDropdown,
        const SizedBox(width: AppSpacing.md),
        sortDropdown,
      ],
    );
  }

  Widget _buildMobileTransactionList(List<Transaction> transactions) {
    return Column(
      children: transactions.map((t) {
        final isInbound = t.type.toLowerCase() == 'receive' ||
            t.type.toLowerCase() == 'inbound';
        final dateStr = t.createdAt != null
            ? '${t.createdAt!.year}-${t.createdAt!.month.toString().padLeft(2, '0')}-${t.createdAt!.day.toString().padLeft(2, '0')}'
            : 'N/A';

        return Column(
          children: [
            InkWell(
              onTap: () => _showTransactionDetails(t),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            t.billNo,
                            style: AppTextStyles.mono.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(
                          label: isInbound ? 'Receive' : 'Release',
                          tone:
                              isInbound ? BadgeTone.success : BadgeTone.danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          dateStr,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.person_outline_rounded,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _getCreatedByName(t),
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.neutralSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${t.formattedTotalItems} total items',
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (_canCancelTransactions)
                          IconButton(
                            onPressed: () => _onDeleteTransaction(t),
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18, color: AppColors.danger),
                            splashRadius: 18,
                            tooltip: 'Delete Transaction',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildDesktopTransactionTable(List<Transaction> transactions) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text('BILL NO.', style: AppTextStyles.label),
              ),
              Expanded(
                flex: 2,
                child: Text('TYPE', style: AppTextStyles.label),
              ),
              Expanded(
                flex: 3,
                child: Text('CREATED BY', style: AppTextStyles.label),
              ),
              Expanded(
                flex: 2,
                child: Text('TOTAL ITEMS',
                    textAlign: TextAlign.right, style: AppTextStyles.label),
              ),
              if (_canCancelTransactions) const SizedBox(width: 48),
            ],
          ),
        ),
        const Divider(height: 0.6, thickness: 0.6),
        ...transactions.expand((t) {
          final isInbound = t.type.toLowerCase() == 'receive' ||
              t.type.toLowerCase() == 'inbound';
          final dateStr = t.createdAt != null
              ? '${t.createdAt!.year}-${t.createdAt!.month.toString().padLeft(2, '0')}-${t.createdAt!.day.toString().padLeft(2, '0')}'
              : 'N/A';

          return [
            InkWell(
              onTap: () => _showTransactionDetails(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.billNo,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.mono.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: StatusBadge(
                        label: isInbound ? 'Receive' : 'Release',
                        tone: isInbound ? BadgeTone.success : BadgeTone.danger,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _getCreatedByName(t),
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        t.formattedTotalItems,
                        textAlign: TextAlign.right,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                    if (_canCancelTransactions)
                      SizedBox(
                        width: 48,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            onPressed: () => _onDeleteTransaction(t),
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 19, color: AppColors.danger),
                            splashRadius: 18,
                            tooltip: 'Delete Transaction',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 0.6, thickness: 0.6),
          ];
        }),
      ],
    );
  }
}
