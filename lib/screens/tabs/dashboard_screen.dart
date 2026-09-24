import 'package:flutter/material.dart';
import '../../models/transaction.dart';
import '../../services/offline_queue_service.dart';
import '../../services/product_service.dart';
import '../../services/transaction_service.dart';
import '../../services/hardware_context.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/top_header_bar.dart';
import '../dialogs_screen/add_product_dialog.dart';
import '../dialogs_screen/add_transaction_screen.dart';
import '../transaction_receipt_screen.dart';
import 'account_screen.dart';

class DashboardScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigateToTab;

  const DashboardScreen({super.key, this.onNavigateToTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _totalProducts = 0;
  int _lowStockCount = 0;
  List<Transaction> _recentTransactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _loading = true);
    try {
      final totalFuture = ProductService.instance.getTotalCount();
      final lowStockFuture = ProductService.instance.getLowStockCount();
      final recentTxnsFuture = TransactionService.instance.getRecent(limit: 5);

      final results = await Future.wait([
        totalFuture,
        lowStockFuture,
        recentTxnsFuture,
      ]);

      final recentTxns = results[2] as List<Transaction>;
      final pendingLocal = OfflineQueueService.instance.getAll().map((p) {
        return Transaction(
          billNo: p.billNo,
          type: p.type,
          totalItems: p.items.fold<double>(0.0, (sum, item) => sum + item.quantity),
          remarks: p.remarks,
          createdBy: p.userId,
          createdAt: p.queuedAt,
          items: p.items,
          localId: p.localId,
          isPendingSync: true,
        );
      }).toList();

      final combined = [...pendingLocal, ...recentTxns];
      final displayTxns = combined.length > 5 ? combined.sublist(0, 5) : combined;

      if (!mounted) return;
      setState(() {
        _totalProducts = results[0] as int;
        _lowStockCount = results[1] as int;
        _recentTransactions = displayTxns;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _onAddProduct() async {
    await AddProductDialog.show(
      context,
      onProductAdded: _loadDashboardData,
    );
    _loadDashboardData();
  }

  Future<void> _onReceive() async {
    final added = await AddTransactionScreen.show(context, initialType: 'Receive');
    if (added == true) {
      _loadDashboardData();
    }
  }

  Future<void> _onRelease() async {
    final added = await AddTransactionScreen.show(context, initialType: 'Release');
    if (added == true) {
      _loadDashboardData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width < 520 ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding:
          EdgeInsets.fromLTRB(horizontalPadding, 28, horizontalPadding, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TopHeaderBar(
            title: 'Dashboard',
            subtitle:
                'Welcome back — here\'s what\'s happening in your warehouse.',
            onAccountTap: () {
              if (widget.onNavigateToTab != null) {
                widget.onNavigateToTab!(5);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const Scaffold(body: AccountScreen())),
                );
              }
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildStatGrid(context),
          const SizedBox(height: AppSpacing.lg),
          _buildMiddleSection(context),
          const SizedBox(height: AppSpacing.lg),
          _buildRecentTransactions(context),
        ],
      ),
    );
  }

  Widget _buildStatGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          StatCard(
            label: 'Total Products',
            value: _loading ? '...' : '$_totalProducts',
            icon: Icons.inventory_2_rounded,
            iconColor: AppColors.primary,
            iconBg: AppColors.primarySoft,
          ),
          StatCard(
            label: 'Low Stock Alert',
            value: _loading ? '...' : '$_lowStockCount',
            icon: Icons.warning_rounded,
            iconColor: AppColors.warning,
            iconBg: AppColors.warningSoft,
            badgeText: _lowStockCount > 0 ? 'Needs review' : 'Optimal',
            badgeTone:
                _lowStockCount > 0 ? BadgeTone.warning : BadgeTone.success,
          ),
        ];

        if (constraints.maxWidth <= 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1)
                  const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        }

        if (constraints.maxWidth <= 900) {
          final itemWidth = (constraints.maxWidth - AppSpacing.md) / 2;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children:
                cards.map((c) => SizedBox(width: itemWidth, child: c)).toList(),
          );
        }

        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1) const SizedBox(width: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMiddleSection(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = _buildQuickActions();
        return actions;
      },
    );
  }

  Widget _buildQuickActions() {
    final canAddProduct = HardwareContext.instance.canAddProducts;
    final canAddTransaction = HardwareContext.instance.canAddTransactions;

    final hasAnyAction = canAddProduct || canAddTransaction;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Actions', style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text(
            hasAnyAction
                ? 'Common tasks, one tap away.'
                : 'No quick actions available for your role.',
            style: AppTextStyles.caption,
          ),
          if (hasAnyAction) ...[
            const SizedBox(height: AppSpacing.lg),
            if (canAddProduct) ...[
              _QuickActionButton(
                icon: Icons.add_circle_rounded,
                label: 'Add Product',
                iconColor: AppColors.primary,
                iconBg: AppColors.primarySoft,
                onTap: _onAddProduct,
              ),
              if (canAddTransaction) const SizedBox(height: AppSpacing.sm),
            ],
            if (canAddTransaction) ...[
              _QuickActionButton(
                icon: Icons.arrow_downward_rounded,
                label: 'Receive Stock',
                iconColor: AppColors.success,
                iconBg: AppColors.successSoft,
                onTap: _onReceive,
              ),
              const SizedBox(height: AppSpacing.sm),
              _QuickActionButton(
                icon: Icons.arrow_upward_rounded,
                label: 'Release Stock',
                iconColor: AppColors.danger,
                iconBg: const Color(0x1AEF4444),
                onTap: _onRelease,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Transactions', style: AppTextStyles.h3),
              TextButton(
                onPressed: _loadDashboardData,
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: Text('Refresh',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _loading
              ? const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                )
              : _recentTransactions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No recent transactions recorded yet.',
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : _TransactionsTable(transactions: _recentTransactions),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.iconBg,
    required this.onTap,
  });

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hovering ? AppColors.background : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: widget.iconBg,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(widget.icon, size: 17, color: widget.iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(widget.label, style: AppTextStyles.bodyMedium)),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionsTable extends StatelessWidget {
  final List<Transaction> transactions;
  const _TransactionsTable({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 500;

    return Column(
      children: [
        if (!compact) ...[
          // Header row.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('BILL NO.', style: AppTextStyles.label)),
                Expanded(flex: 2, child: Text('TYPE', style: AppTextStyles.label)),
                Expanded(
                  flex: 2,
                  child: Text('TOTAL ITEMS',
                      textAlign: TextAlign.right, style: AppTextStyles.label),
                ),
              ],
            ),
          ),
          const Divider(height: 0.6, thickness: 0.6),
        ],
        // Data rows.
        ...transactions.expand((t) {
          final inbound = t.type.toLowerCase() == 'receive' ||
              t.type.toLowerCase() == 'inbound' ||
              t.type.toLowerCase() == 'purchase';
          final dateStr = t.createdAt != null
              ? '${t.createdAt!.year}-${t.createdAt!.month.toString().padLeft(2, '0')}-${t.createdAt!.day.toString().padLeft(2, '0')}'
              : 'N/A';

          Future<void> openDetails() async {
            try {
              final detailedTxn = t.id != null
                  ? await TransactionService.instance.getById(t.id!)
                  : t;
              if (!context.mounted) return;
              TransactionReceiptScreen.navigateTo(context, detailedTxn);
            } catch (e) {
              if (!context.mounted) return;
              TransactionReceiptScreen.navigateTo(context, t);
            }
          }

          if (compact) {
            return [
              InkWell(
                onTap: openDetails,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              t.billNo,
                              style: AppTextStyles.mono.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          StatusBadge(
                            label: inbound ? 'Receive' : 'Release',
                            tone: inbound ? BadgeTone.success : BadgeTone.danger,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dateStr,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '${t.totalItems} items',
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 0.6, thickness: 0.6),
            ];
          }

          return [
            InkWell(
              onTap: openDetails,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.billNo,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.mono
                                .copyWith(fontWeight: FontWeight.w600),
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
                        label: inbound ? 'Receive' : 'Release',
                        tone: inbound ? BadgeTone.success : BadgeTone.danger,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${t.totalItems}',
                        textAlign: TextAlign.right,
                        style: AppTextStyles.bodyMedium,
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