import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/product.dart';
import '../models/transaction.dart';
import '../services/product_service.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/pdf_preview_screen.dart';
import 'dialogs_screen/add_transaction_screen.dart';
import 'transaction_receipt_screen.dart';

String _formatNum(num? val) {
  if (val == null) return '';
  if (val % 1 == 0) return val.toInt().toString();
  return val.toString().replaceAll(RegExp(r'([.]*0)(?!.*\d)'), '');
}

class _LedgerEntry {
  final Transaction transaction;
  final String billNo;
  final DateTime? date;
  final double? receiveQty;
  final double? releaseQty;
  final double balance;

  _LedgerEntry({
    required this.transaction,
    required this.billNo,
    required this.date,
    required this.receiveQty,
    required this.releaseQty,
    required this.balance,
  });

  String get formattedReceive =>
      receiveQty != null ? _formatNum(receiveQty) : '';
  String get formattedRelease =>
      releaseQty != null ? _formatNum(releaseQty) : '';
  String get formattedBalance => _formatNum(balance);
}

class ProductLedgerScreen extends StatefulWidget {
  final Product product;

  const ProductLedgerScreen({super.key, required this.product});

  static Future<void> navigateTo(BuildContext context, Product product) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductLedgerScreen(product: product),
      ),
    );
  }

  @override
  State<ProductLedgerScreen> createState() => _ProductLedgerScreenState();
}

class _ProductLedgerScreenState extends State<ProductLedgerScreen> {
  late Product _product;
  List<_LedgerEntry> _entries = [];
  bool _loading = true;
  String? _error;

  final DateFormat _dateFormat = DateFormat('MMMM dd, yyyy');
  pw.MemoryImage? _cachedLogoImage;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _initData();
  }

  Future<void> _initData() async {
    try {
      final logoBytes = await rootBundle.load('assets/images/clogo.png');
      _cachedLogoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('[ProductLedger] Logo load error: $e');
    }
    await _loadLedger();
  }

  Future<void> _loadLedger() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_product.id == null) {
        setState(() => _loading = false);
        return;
      }

      // Fetch fresh product info for current stock
      final updatedProduct =
          await ProductService.instance.getById(_product.id!);
      if (updatedProduct != null) {
        _product = updatedProduct;
      }

      // Fetch transactions involving this product in chronological order
      final txns =
          await TransactionService.instance.getByProductId(_product.id!);

      // Calculate total net change across all recorded transactions
      double totalNetChange = 0.0;
      final List<({Transaction txn, double qty, bool isReceive, double delta})>
          deltas = [];

      for (final t in txns) {
        double itemQty = 0.0;
        for (final item in t.items) {
          if (item.productId == _product.id ||
              item.productName.trim().toLowerCase() ==
                  _product.productName.trim().toLowerCase()) {
            itemQty += item.quantity;
          }
        }
        if (itemQty == 0) {
          itemQty = t.totalItems > 0 ? t.totalItems : 1.0;
        }

        final isReceive = t.type.toLowerCase() == 'receive' ||
            t.type.toLowerCase() == 'inbound' ||
            t.type.toLowerCase() == 'purchase';

        final delta = isReceive ? itemQty : -itemQty;
        totalNetChange += delta;
        deltas.add((txn: t, qty: itemQty, isReceive: isReceive, delta: delta));
      }

      // Replay from initial opening stock to guarantee the latest balance matches current stock
      double runningBalance = _product.quantity - totalNetChange;
      final List<_LedgerEntry> computed = [];

      for (final d in deltas) {
        runningBalance += d.delta;
        computed.add(_LedgerEntry(
          transaction: d.txn,
          billNo: d.txn.billNo,
          date: d.txn.createdAt,
          receiveQty: d.isReceive ? d.qty : null,
          releaseQty: !d.isReceive ? d.qty : null,
          balance: runningBalance,
        ));
      }

      if (!mounted) return;
      setState(() {
        _entries = computed.reversed.toList();
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

  Future<void> _onReceive() async {
    final result = await AddTransactionScreen.show(
      context,
      initialType: 'Receive',
      initialProduct: _product,
    );
    if (result == true) {
      _loadLedger();
    }
  }

  Future<void> _onRelease() async {
    final result = await AddTransactionScreen.show(
      context,
      initialType: 'Release',
      initialProduct: _product,
    );
    if (result == true) {
      _loadLedger();
    }
  }

  Future<void> _openTransactionReceipt(Transaction txn) async {
    try {
      final fullTxn = txn.id != null
          ? await TransactionService.instance.getById(txn.id!)
          : txn;
      if (!mounted) return;
      await TransactionReceiptScreen.navigateTo(context, fullTxn);
      if (mounted) {
        _loadLedger();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load transaction details: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<Uint8List> _buildPdfBytes(PdfPageFormat format) async {
    final pdf = pw.Document();
    final generatedAtStr =
        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    final headers = ['Description', 'Date', 'Receive', 'Release', 'Balance'];
    final dataRows = _entries.map((e) {
      final dStr = e.date != null ? _dateFormat.format(e.date!) : 'N/A';
      return [
        e.billNo,
        dStr,
        e.receiveQty != null ? '+${e.formattedReceive}' : '',
        e.releaseQty != null ? '-${e.formattedRelease}' : '',
        e.formattedBalance,
      ];
    }).toList();

    final logoImage = _cachedLogoImage;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logoImage != null) ...[
                        pw.Image(logoImage, width: 38, height: 38),
                        pw.SizedBox(width: 10),
                      ],
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'STOKADO',
                            style: const pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red800,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Stock Card / Product Ledger',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Text(
                    generatedAtStr,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600),
                  ),
                ],
              ),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 8),
            ],
          );
        },
        build: (pw.Context ctx) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _product.productName.toUpperCase(),
                      style: const pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Unit: ${_product.unit}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('CURRENT STOCK',
                          style: const pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey700)),
                      pw.Text('${_product.quantity} ${_product.unit}',
                          style: const pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red800)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: dataRows.isEmpty
                  ? [
                      [
                        'No transactions recorded',
                        '-',
                        '-',
                        '-',
                        '${_product.quantity}'
                      ]
                    ]
                  : dataRows,
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerStyle: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> _exportPdf() async {
    await PdfPreviewScreen.navigateTo(
      context,
      title: 'Stock Card - ${_product.productName}',
      buildPdf: _buildPdfBytes,
      fileName: 'StockCard_${_product.productName.replaceAll(" ", "_")}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(_product.productName, style: AppTextStyles.h3),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SecondaryButton(
              label: 'Export PDF',
              icon: Icons.picture_as_pdf_outlined,
              onPressed: _exportPdf,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Failed to load ledger', style: AppTextStyles.h3),
                      const SizedBox(height: 6),
                      Text(_error!,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.danger)),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: _loadLedger,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadLedger,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 600;
                      final padding = compact ? 16.0 : 28.0;

                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(padding, 20, padding, 100),
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 1000),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Product Header Box
                                Container(
                                  padding: EdgeInsets.all(compact ? 16 : 24),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.border),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.03),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: compact
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _product.productName
                                                  .toUpperCase(),
                                              style: AppTextStyles.h2.copyWith(
                                                  fontSize: 18,
                                                  letterSpacing: 0.5),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'Unit: ${_product.unit}  •  ${_entries.length} moves',
                                                  style: AppTextStyles.caption
                                                      .copyWith(
                                                          color: AppColors
                                                              .textSecondary),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        AppColors.primarySoft,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Text(
                                                        'STOCK: ',
                                                        style: AppTextStyles
                                                            .caption
                                                            .copyWith(
                                                                color: AppColors
                                                                    .primary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 10),
                                                      ),
                                                      Text(
                                                        '${_product.quantity}',
                                                        style: AppTextStyles.h3
                                                            .copyWith(
                                                                color: AppColors
                                                                    .primary,
                                                                fontSize: 18),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _product.productName
                                                        .toUpperCase(),
                                                    style: AppTextStyles.h1
                                                        .copyWith(
                                                            fontSize: 22,
                                                            letterSpacing: 0.5),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Unit: ${_product.unit}  •  ${_entries.length} recorded movements',
                                                    style: AppTextStyles.caption
                                                        .copyWith(
                                                            color: AppColors
                                                                .textSecondary),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 12),
                                              decoration: BoxDecoration(
                                                color: AppColors.primarySoft,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                    color: AppColors.primary
                                                        .withValues(
                                                            alpha: 0.2)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    'TOTAL STOCK',
                                                    style: AppTextStyles.label
                                                        .copyWith(
                                                            color: AppColors
                                                                .primary,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${_product.quantity}',
                                                    style: AppTextStyles.h1
                                                        .copyWith(
                                                            color: AppColors
                                                                .primary,
                                                            fontSize: 28),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                ),

                                const SizedBox(height: 20),

                                // Ledger Table Card
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.border),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.03),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      if (!compact) ...[
                                        // Desktop Table Header
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 14),
                                          decoration: const BoxDecoration(
                                            color: AppColors.neutralSoft,
                                            borderRadius: BorderRadius.vertical(
                                                top: Radius.circular(15)),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 5,
                                                child: Text('DESCRIPTION',
                                                    style: AppTextStyles.label),
                                              ),
                                              SizedBox(
                                                width: 90,
                                                child: Text('RECEIVE',
                                                    textAlign: TextAlign.center,
                                                    style: AppTextStyles.label
                                                        .copyWith(
                                                            color: AppColors
                                                                .success)),
                                              ),
                                              SizedBox(
                                                width: 90,
                                                child: Text('RELEASE',
                                                    textAlign: TextAlign.center,
                                                    style: AppTextStyles.label
                                                        .copyWith(
                                                            color: AppColors
                                                                .danger)),
                                              ),
                                              SizedBox(
                                                width: 90,
                                                child: Text('BALANCE',
                                                    textAlign: TextAlign.right,
                                                    style: AppTextStyles.label),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Divider(
                                            height: 1, color: AppColors.border),
                                      ],

                                      // Table Rows
                                      if (_entries.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.all(40.0),
                                          child: Center(
                                            child: Text(
                                              'No transaction history for this item yet.',
                                              style: AppTextStyles.body
                                                  .copyWith(
                                                      color: AppColors
                                                          .textSecondary),
                                            ),
                                          ),
                                        )
                                      else
                                        ..._entries.map((entry) {
                                          final dateStr = entry.date != null
                                              ? _dateFormat.format(entry.date!)
                                              : 'N/A';

                                          if (compact) {
                                            return Column(
                                              children: [
                                                InkWell(
                                                  onTap: () => _openTransactionReceipt(entry.transaction),
                                                  child: Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 16,
                                                        vertical: 12),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  entry.billNo,
                                                                  style: AppTextStyles
                                                                      .bodyMedium
                                                                      .copyWith(
                                                                          fontWeight:
                                                                              FontWeight
                                                                                  .w600,
                                                                          color: AppColors
                                                                              .primary),
                                                                ),
                                                                const SizedBox(width: 4),
                                                                const Icon(
                                                                  Icons.chevron_right_rounded,
                                                                  size: 16,
                                                                  color: AppColors.textMuted,
                                                                ),
                                                              ],
                                                            ),
                                                            if (entry
                                                                    .receiveQty !=
                                                                null)
                                                              Text(
                                                                '+${entry.receiveQty}',
                                                                style: AppTextStyles
                                                                    .bodyMedium
                                                                    .copyWith(
                                                                        color: AppColors
                                                                            .success,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .bold),
                                                              )
                                                            else if (entry
                                                                    .releaseQty !=
                                                                null)
                                                              Text(
                                                                '-${entry.releaseQty}',
                                                                style: AppTextStyles
                                                                    .bodyMedium
                                                                    .copyWith(
                                                                        color: AppColors
                                                                            .danger,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .bold),
                                                              ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Text(
                                                              dateStr,
                                                              style: AppTextStyles
                                                                  .caption
                                                                  .copyWith(
                                                                      fontSize:
                                                                          12,
                                                                      color: AppColors
                                                                          .textSecondary),
                                                            ),
                                                            Text(
                                                              'Bal: ${entry.balance}',
                                                              style: AppTextStyles
                                                                  .caption
                                                                  .copyWith(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      color: AppColors
                                                                          .textPrimary),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const Divider(
                                                    height: 1,
                                                    color: AppColors.border),
                                              ],
                                            );
                                          }

                                          return Column(
                                            children: [
                                              InkWell(
                                                onTap: () => _openTransactionReceipt(entry.transaction),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 20,
                                                          vertical: 14),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.center,
                                                    children: [
                                                      // Description (Bill No. + Date subtext)
                                                      Expanded(
                                                        flex: 5,
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  entry.billNo,
                                                                  style: AppTextStyles
                                                                      .bodyMedium
                                                                      .copyWith(
                                                                          fontWeight:
                                                                              FontWeight
                                                                                  .w600,
                                                                          color: AppColors
                                                                              .primary),
                                                                ),
                                                                const SizedBox(width: 4),
                                                                const Icon(
                                                                  Icons.arrow_outward_rounded,
                                                                  size: 14,
                                                                  color: AppColors.textMuted,
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(
                                                                height: 2),
                                                            Text(
                                                              dateStr,
                                                              style: AppTextStyles
                                                                  .caption
                                                                  .copyWith(
                                                                      fontSize:
                                                                          12,
                                                                      color: AppColors
                                                                          .textSecondary),
                                                            ),
                                                          ],
                                                        ),
                                                      ),

                                                      // Receive Column (+ sign with green)
                                                      SizedBox(
                                                        width: 90,
                                                        child:
                                                            entry.receiveQty !=
                                                                    null
                                                                ? Text(
                                                                    '+${entry.formattedReceive}',
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style: AppTextStyles
                                                                        .bodyMedium
                                                                        .copyWith(
                                                                            color: AppColors
                                                                                .success,
                                                                            fontWeight:
                                                                                FontWeight.bold),
                                                                  )
                                                                : const SizedBox
                                                                    .shrink(),
                                                      ),

                                                      // Release Column (- sign with red)
                                                      SizedBox(
                                                        width: 90,
                                                        child:
                                                            entry.releaseQty !=
                                                                    null
                                                                ? Text(
                                                                    '-${entry.formattedRelease}',
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style: AppTextStyles
                                                                        .bodyMedium
                                                                        .copyWith(
                                                                            color: AppColors
                                                                                .danger,
                                                                            fontWeight:
                                                                                FontWeight.bold),
                                                                  )
                                                                : const SizedBox
                                                                    .shrink(),
                                                      ),

                                                      // Balance Column
                                                      SizedBox(
                                                        width: 90,
                                                        child: Text(
                                                          entry.formattedBalance,
                                                          textAlign:
                                                              TextAlign.right,
                                                          style: AppTextStyles
                                                              .bodyMedium
                                                              .copyWith(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: AppColors
                                                                      .textPrimary),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const Divider(
                                                  height: 1,
                                                  color: AppColors.border),
                                            ],
                                          );
                                        }),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      bottomNavigationBar: SafeArea(
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
    );
  }
}
