import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/product.dart';
import '../../models/transaction.dart';
import '../../models/transaction_item.dart';
import '../../services/auth_service.dart';
import '../../services/product_service.dart';
import '../../services/transaction_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/notification_banner.dart';
import '../transaction_receipt_screen.dart';

class _TxnItemRow {
  final Key key = UniqueKey();
  Product? selectedProduct;
  final TextEditingController quantityController;

  _TxnItemRow({String initialQty = '1'})
      : quantityController = TextEditingController(text: initialQty);

  void dispose() {
    quantityController.dispose();
  }
}

/// A full screen to record or edit an Inbound/Outbound Stock Transaction.
///
/// Pass [existingTransaction] to open in edit mode: fields are pre-filled
/// and submitting calls [TransactionService.update] instead of
/// [TransactionService.create]. Editing does not change product stock —
/// use the separate cancel flow to reverse stock.
class AddTransactionScreen extends StatefulWidget {
  final Transaction? existingTransaction;
  final String initialType;
  final Product? initialProduct;

  const AddTransactionScreen({
    super.key,
    this.existingTransaction,
    this.initialType = 'Receive',
    this.initialProduct,
  });

  /// Pushes the screen in create mode. Returns `true` if a transaction was created.
  static Future<bool?> show(
    BuildContext context, {
    String initialType = 'Receive',
    Product? initialProduct,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          initialType: initialType,
          initialProduct: initialProduct,
        ),
      ),
    );
  }

  /// Pushes the screen in edit mode for an existing transaction.
  /// Returns `true` if the transaction was updated.
  static Future<bool?> showEdit(BuildContext context, Transaction transaction) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(existingTransaction: transaction),
      ),
    );
  }

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _billNoController = TextEditingController();
  final _remarksController = TextEditingController();
  late DateTime _selectedDate;

  late String _type;
  List<Product> _allProducts = [];
  bool _loadingProducts = true;
  bool _submitting = false;
  
  final List<_TxnItemRow> _itemRows = [];

  bool get _isEditMode => widget.existingTransaction != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTransaction;
    _selectedDate = existing?.createdAt ?? DateTime.now();
    if (existing != null) {
      _billNoController.text = existing.billNo;
      if (existing.remarks != null && existing.remarks != 'N/A') {
        _remarksController.text = existing.remarks!;
      }
    }
    _type = _isEditMode
        ? widget.existingTransaction!.type
        : widget.initialType;
    _loadProducts();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDate.hour,
          _selectedDate.minute,
          _selectedDate.second,
        );
      });
    }
  }

  Widget _buildDateField() {
    final formattedDate = DateFormat('MMM dd, yyyy').format(_selectedDate);
    return _buildField(
      label: 'Date',
      child: InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text(
                    formattedDate,
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
              IconButton(
                onPressed: _pickDate,
                icon: const Icon(Icons.edit_calendar_rounded,
                    size: 18, color: AppColors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Select Date',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _billNoController.dispose();
    _remarksController.dispose();
    for (final row in _itemRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await ProductService.instance.getAll();
      if (!mounted) return;
      setState(() {
        _allProducts = products;
        _loadingProducts = false;

        if (_itemRows.isEmpty) {
          if (_isEditMode &&
              widget.existingTransaction!.items.isNotEmpty) {
            for (final item in widget.existingTransaction!.items) {
              final row = _TxnItemRow(
                initialQty: item.formattedQuantity,
              );
              if (item.productId != null) {
                for (final p in products) {
                  if (p.id == item.productId) {
                    row.selectedProduct = p;
                    break;
                  }
                }
              }
              _itemRows.add(row);
            }
          } else {
            final row = _TxnItemRow();
            if (widget.initialProduct != null) {
              for (final p in products) {
                if (p.id == widget.initialProduct!.id) {
                  row.selectedProduct = p;
                  break;
                }
              }
              row.selectedProduct ??= widget.initialProduct;
            }
            _itemRows.add(row);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingProducts = false);
    }
  }

  void _addItemRow() {
    setState(() {
      _itemRows.insert(0, _TxnItemRow());
    });
  }

  void _removeItemRow(int index) {
    if (_itemRows.length <= 1) return;
    setState(() {
      final removed = _itemRows.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final validItems = <TransactionItem>[];
    for (int i = 0; i < _itemRows.length; i++) {
      final row = _itemRows[i];
      if (row.selectedProduct == null) {
        NotificationBanner.show(
          context,
          'Please select a product for item #${i + 1}.',
          tone: NotificationTone.warning,
        );
        return;
      }

      final allowsDecimals = row.selectedProduct!.unit.trim().toLowerCase() == 'kg' ||
          row.selectedProduct!.unit.trim().toLowerCase() == 'cubic';

      final rawQty = row.quantityController.text.trim().replaceAll(',', '.');
      if (!allowsDecimals && rawQty.contains(RegExp(r'[\.,]'))) {
        NotificationBanner.show(
          context,
          '${row.selectedProduct!.productName} (${row.selectedProduct!.unit}) only accepts whole numbers.',
          tone: NotificationTone.warning,
        );
        return;
      }

      final parsedQty = double.tryParse(rawQty) ?? 0.0;
      final qty = allowsDecimals ? parsedQty : parsedQty.truncateToDouble();
      if (qty <= 0) {
        NotificationBanner.show(
          context,
          'Quantity for ${row.selectedProduct!.productName} must be greater than 0.',
          tone: NotificationTone.warning,
        );
        return;
      }

      if (!_isEditMode &&
          _type.toLowerCase() == 'release' &&
          qty > row.selectedProduct!.quantity) {
        NotificationBanner.show(
          context,
          'Warning: ${row.selectedProduct!.productName} only has ${row.selectedProduct!.formattedQuantity} ${row.selectedProduct!.unit} in stock.',
          tone: NotificationTone.warning,
        );
      }

      validItems.add(TransactionItem(
        productId: row.selectedProduct!.id,
        productName: row.selectedProduct!.productName,
        quantity: qty,
      ));
    }

    setState(() => _submitting = true);
    try {
      if (_isEditMode) {
        await TransactionService.instance.update(
          transactionId: widget.existingTransaction!.id!,
          billNo: _billNoController.text.trim(),
          type: _type,
          items: validItems,
          remarks: _remarksController.text.trim(),
          createdAt: _selectedDate,
        );

        if (!mounted) return;
        NotificationBanner.show(
          context,
          'Transaction updated successfully!',
          tone: NotificationTone.success,
        );
        Navigator.of(context).pop(true);
      } else {
        final currentUserId = AuthService.instance.userId;

        final createdTxn = await TransactionService.instance.create(
          billNo: _billNoController.text.trim(),
          type: _type,
          items: validItems,
          remarks: _remarksController.text.trim(),
          userId: currentUserId,
          createdAt: _selectedDate,
        );

        if (!mounted) return;
        NotificationBanner.show(
          context,
          'Transaction created successfully!',
          tone: NotificationTone.success,
        );
        Navigator.of(context).pop(true);
        TransactionReceiptScreen.navigateTo(context, createdTxn);
      }
    } catch (e, st) {
      debugPrint('[AddTransactionScreen] Error saving transaction: $e\n$st');
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Failed to save transaction: $e',
        tone: NotificationTone.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isReceive = _type.toLowerCase() == 'receive';
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isReceive ? AppColors.successSoft : AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                    _isEditMode
                        ? Icons.edit_rounded
                        : (isReceive
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded),
                    color: isReceive ? AppColors.success : AppColors.danger,
                    size: 22),
              ),
            ),
            const SizedBox(width: 14),
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      _isEditMode
                          ? 'Edit Transaction'
                          : (isReceive
                              ? 'Receive Stock'
                              : 'Release Stock'),
                      style: AppTextStyles.h3),
                  const SizedBox(height: 2),
                  Text(
                      _isEditMode
                          ? 'Update this transaction\'s details.'
                          : (isReceive
                              ? 'Record incoming stock movement.'
                              : 'Record outgoing stock movement.'),
                      style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final padding = compact ? 16.0 : 20.0;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 8),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bill No
                  _buildField(
                    label: 'Bill No. / Reference',
                    child: TextFormField(
                      controller: _billNoController,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textPrimary),
                      decoration: _inputDecoration('e.g. BILL-1001'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Remarks & Date Row
                  if (compact) ...[
                    _buildField(
                      label: 'Remarks (Optional)',
                      child: TextFormField(
                        controller: _remarksController,
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.textPrimary),
                        decoration: _inputDecoration('Notes / Purpose'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDateField(),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildField(
                            label: 'Remarks (Optional)',
                            child: TextFormField(
                              controller: _remarksController,
                              style: AppTextStyles.body
                                  .copyWith(color: AppColors.textPrimary),
                              decoration: _inputDecoration('Notes / Purpose'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _buildDateField(),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Item List Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Items in Transaction', style: AppTextStyles.h3.copyWith(fontSize: compact ? 16 : 18)),
                      TextButton.icon(
                        onPressed: _addItemRow,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text('Add Item',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.primary, fontSize: compact ? 13 : 14)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_loadingProducts)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_allProducts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.warningSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.warning),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No products found in inventory. Please add products first before creating a transaction.',
                              style: AppTextStyles.body,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._itemRows.asMap().entries.map((entry) {
                      final i = entry.key;
                      final row = entry.value;

                      final selectedProduct = row.selectedProduct != null
                          ? _allProducts.firstWhere(
                              (p) => p.id == row.selectedProduct!.id,
                              orElse: () => row.selectedProduct!,
                            )
                          : null;

                      final autocompleteWidget = Autocomplete<Product>(
                        displayStringForOption: (p) => p.productName,
                        initialValue: TextEditingValue(
                          text: selectedProduct?.productName ?? '',
                        ),
                        optionsBuilder: (TextEditingValue textValue) {
                          if (textValue.text.isEmpty) {
                            return _allProducts;
                          }
                          return _allProducts.where((p) => p.productName
                              .toLowerCase()
                              .contains(textValue.text.toLowerCase()));
                        },
                        onSelected: (Product p) {
                          setState(() {
                            final existingRow = _itemRows.firstWhere(
                              (r) => r != row && r.selectedProduct?.id == p.id,
                              orElse: () => _TxnItemRow(),
                            );

                            final foundDuplicate =
                                _itemRows.contains(existingRow) &&
                                    existingRow != row;

                            if (foundDuplicate) {
                              final thisQty = int.tryParse(
                                      row.quantityController.text) ??
                                  0;
                              final existingQty = int.tryParse(
                                      existingRow.quantityController.text) ??
                                  0;
                              existingRow.quantityController.text =
                                  (existingQty + thisQty).toString();

                              _itemRows.remove(row);
                            } else {
                              row.selectedProduct = p;
                            }
                          });
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.textPrimary),
                            decoration: _inputDecoration('Search product name...'),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(12),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: 250,
                                  maxWidth: compact ? (constraints.maxWidth - 32) : 400,
                                ),
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final p = options.elementAt(index);
                                    return ListTile(
                                      title: Text(
                                        p.productName,
                                        style: AppTextStyles.bodyMedium.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'In stock: ${p.formattedQuantity} ${p.unit}',
                                        style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      onTap: () {
                                        final allowsDecimals = p.unit.trim().toLowerCase() == 'kg' ||
                                            p.unit.trim().toLowerCase() == 'cubic';
                                        if (!allowsDecimals) {
                                          final raw = row.quantityController.text.trim().replaceAll(',', '.');
                                          final val = double.tryParse(raw);
                                          if (val != null) {
                                            row.quantityController.text = val.toInt().toString();
                                          }
                                        }
                                        onSelected(p);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      );

                      final allowsDecimals = row.selectedProduct != null &&
                          (row.selectedProduct!.unit.trim().toLowerCase() == 'kg' ||
                           row.selectedProduct!.unit.trim().toLowerCase() == 'cubic');

                      final qtyStepperWidget = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 68,
                            child: TextFormField(
                              controller: row.quantityController,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.body.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600),
                              decoration: _inputDecoration('Qty'),
                              keyboardType: allowsDecimals
                                  ? const TextInputType.numberWithOptions(decimal: true)
                                  : TextInputType.number,
                              inputFormatters: [
                                if (allowsDecimals)
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*[\.,]?\d*'))
                                else
                                  FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                InkWell(
                                  onTap: () {
                                    final raw = row.quantityController.text.trim().replaceAll(',', '.');
                                    final current = double.tryParse(raw) ?? 0.0;
                                    final next = current + 1.0;
                                    row.quantityController.text = next % 1 == 0
                                        ? next.toInt().toString()
                                        : next.toString();
                                  },
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8)),
                                  child: const SizedBox(
                                    width: 26,
                                    height: 22,
                                    child: Icon(Icons.keyboard_arrow_up_rounded,
                                        size: 18,
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                                const Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: AppColors.border),
                                InkWell(
                                  onTap: () {
                                    final raw = row.quantityController.text.trim().replaceAll(',', '.');
                                    final current = double.tryParse(raw) ?? 1.0;
                                    if (current > 1.0) {
                                      final next = current - 1.0;
                                      row.quantityController.text = next % 1 == 0
                                          ? next.toInt().toString()
                                          : next.toString();
                                    }
                                  },
                                  borderRadius: const BorderRadius.vertical(
                                      bottom: Radius.circular(8)),
                                  child: const SizedBox(
                                    width: 26,
                                    height: 22,
                                    child: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );

                      if (compact) {
                        return Container(
                          key: row.key,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              autocompleteWidget,
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  qtyStepperWidget,
                                  if (selectedProduct != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.neutralSoft,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Stock: ${selectedProduct.formattedQuantity} ${selectedProduct.unit}',
                                        style: AppTextStyles.caption.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (_itemRows.length > 1)
                                    IconButton(
                                      onPressed: () => _removeItemRow(i),
                                      icon: const Icon(Icons.delete_outline_rounded,
                                          color: AppColors.danger, size: 20),
                                      splashRadius: 18,
                                      tooltip: 'Remove row',
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(6),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }

                      return Container(
                        key: row.key,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: autocompleteWidget,
                            ),
                            const SizedBox(width: 12),
                            qtyStepperWidget,
                            if (_itemRows.length > 1) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: () => _removeItemRow(i),
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: AppColors.danger, size: 20),
                                splashRadius: 18,
                                tooltip: 'Remove row',
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancel', style: AppTextStyles.bodyMedium),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            _isEditMode ? 'Save Changes' : 'Save Transaction',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
      ),
    );
  }
}