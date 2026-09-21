import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/notification_banner.dart';
import '../../widgets/section_card.dart';
import '../dialogs_screen/add_product_dialog.dart';
import '../dialogs_screen/edit_product_dialog.dart';
import '../product_ledger_screen.dart';

enum ProductSort { recentlyAdded, nameAsc, nameDesc }

extension _ProductSortLabel on ProductSort {
  String get label {
    switch (this) {
      case ProductSort.recentlyAdded:
        return 'Recently Added';
      case ProductSort.nameAsc:
        return 'Name (A-Z)';
      case ProductSort.nameDesc:
        return 'Name (Z-A)';
    }
  }
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  bool _loading = true;
  String? _error;
  ProductSort _sortOption = ProductSort.recentlyAdded;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final productsFuture = ProductService.instance.getAll();

      final results = await Future.wait([productsFuture]);

      if (!mounted) return;
      setState(() {
        _products = results[0];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onAddProduct() {
    AddProductDialog.show(
      context,
      onProductAdded: () {
        _loadData();
      },
    );
  }

  Future<void> _onOpenProductLedger(Product p) async {
    await ProductLedgerScreen.navigateTo(context, p);
    _loadData();
  }

  Future<void> _onEditProduct(Product p) async {
    final updated = await EditProductDialog.show(context, p);
    if (updated == true) {
      _loadData();
    }
  }

  Future<void> _onDeleteProduct(Product p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Product', style: AppTextStyles.h3),
        content: Text(
          'Are you sure you want to delete "${p.productName}"?',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppTextStyles.bodyMedium),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && p.id != null) {
      try {
        await ProductService.instance.delete(p.id!);
        if (!mounted) return;
        NotificationBanner.show(
          context,
          'Product "${p.productName}" deleted.',
          tone: NotificationTone.success,
        );
        _loadData();
      } catch (e) {
        if (!mounted) return;
        NotificationBanner.show(
          context,
          'Failed to delete product: $e',
          tone: NotificationTone.error,
        );
      }
    }
  }

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _products.where((p) {
      final matchesQuery =
          query.isEmpty || p.productName.toLowerCase().contains(query);
      return matchesQuery;
    }).toList();

    switch (_sortOption) {
      case ProductSort.nameAsc:
        filtered.sort((a, b) =>
            a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
        break;
      case ProductSort.nameDesc:
        filtered.sort((a, b) =>
            b.productName.toLowerCase().compareTo(a.productName.toLowerCase()));
        break;
      case ProductSort.recentlyAdded:
        // Sort by createdAt desc; Firestore doc IDs are not sortable by creation order.
        filtered.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;
    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 600;
    final horizontalPadding = compact ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 28, horizontalPadding, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'Inventory',
            subtitle: _loading
                ? 'Loading products...'
                : '${_products.length} products in stock',
            actions: [
              PrimaryButton(
                label: 'Add New Product',
                icon: Icons.add_rounded,
                onPressed: _onAddProduct,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildFilterBar(),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
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
                              Text('Failed to load products',
                                  style: AppTextStyles.h3),
                              const SizedBox(height: 8),
                              Text(_error!,
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.danger)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadData,
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
                                _products.isEmpty
                                    ? 'No products added yet. Click "Add New Product" to create one.'
                                    : 'No products match your filter criteria.',
                                style: AppTextStyles.body
                                    .copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                          )
                        : _ProductTable(
                            products: filtered,
                            onSelectProduct: _onOpenProductLedger,
                            onEdit: _onEditProduct,
                            onDelete: _onDeleteProduct,
                          ),
          ),
        ],
      ),
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
                hintText: 'Search product name...',
                hintStyle: AppTextStyles.body
                    .copyWith(color: AppColors.textMuted),
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

    final sortDropdown = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ProductSort>(
          value: _sortOption,
          icon: const Icon(Icons.expand_more_rounded,
              size: 18, color: AppColors.textSecondary),
          style: AppTextStyles.body,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          isExpanded: compact,
          items: ProductSort.values
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.label),
                  ))
              .toList(),
          onChanged: (v) =>
              setState(() => _sortOption = v ?? ProductSort.recentlyAdded),
        ),
      ),
    );

    if (compact) {
      return Column(
        children: [
          searchField,
          const SizedBox(height: AppSpacing.sm),
          sortDropdown,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: AppSpacing.md),
        sortDropdown,
      ],
    );
  }
}

class _ProductTable extends StatelessWidget {
  final List<Product> products;
  final Function(Product) onSelectProduct;
  final Function(Product) onEdit;
  final Function(Product) onDelete;

  const _ProductTable({
    required this.products,
    required this.onSelectProduct,
    required this.onEdit,
    required this.onDelete,
  });

  static const double _stockColumnWidth = 120;
  static const double _actionsColumnWidth = 96;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 600;

    if (compact) {
      return _buildMobileList();
    }
    return _buildDesktopTable();
  }

  Widget _buildMobileList() {
    return Column(
      children: products.map((p) {
        return Column(
          children: [
            InkWell(
              onTap: () => onSelectProduct(p),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name — full display, no ellipsis
                    Text(
                      p.productName,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: p.quantity <= 10
                                ? AppColors.warningSoft
                                : AppColors.successSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${p.formattedQuantity} ${p.unit}',
                            style: AppTextStyles.caption.copyWith(
                              color: p.quantity <= 10
                                  ? AppColors.warning
                                  : AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => onEdit(p),
                          icon: const Icon(Icons.edit_outlined,
                              size: 18, color: AppColors.primary),
                          splashRadius: 18,
                          tooltip: 'Edit',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => onDelete(p),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18, color: AppColors.danger),
                          splashRadius: 18,
                          tooltip: 'Delete',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
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

  Widget _buildDesktopTable() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('PRODUCT NAME', style: AppTextStyles.label),
                ),
                SizedBox(
                  width: _stockColumnWidth,
                  child: Text('IN STOCK',
                      textAlign: TextAlign.right, style: AppTextStyles.label),
                ),
                const SizedBox(width: 28),
                SizedBox(
                  width: _actionsColumnWidth,
                  child: Text('ACTIONS',
                      textAlign: TextAlign.right, style: AppTextStyles.label),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // Data rows
          ...products.map((p) {
            return Column(
              children: [
                InkWell(
                  onTap: () => onSelectProduct(p),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.productName,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: _stockColumnWidth,
                          child: Text(
                            '${p.formattedQuantity} ${p.unit}',
                            textAlign: TextAlign.right,
                            style: AppTextStyles.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 28),
                        SizedBox(
                          width: _actionsColumnWidth,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                onPressed: () => onEdit(p),
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18, color: AppColors.primary),
                                splashRadius: 18,
                                tooltip: 'Edit',
                              ),
                              IconButton(
                                onPressed: () => onDelete(p),
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18, color: AppColors.danger),
                                splashRadius: 18,
                                tooltip: 'Delete',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
              ],
            );
          }),
        ],
      ),
    );
  }
}