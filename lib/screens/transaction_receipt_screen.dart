import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/transaction.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/transaction_service.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/notification_banner.dart';
import '../widgets/pdf_preview_screen.dart';
import '../widgets/status_badge.dart';
import 'dialogs_screen/add_transaction_screen.dart';

class TransactionReceiptScreen extends StatefulWidget {
  final Transaction transaction;

  const TransactionReceiptScreen({super.key, required this.transaction});

  static Future<void> navigateTo(BuildContext context, Transaction txn) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionReceiptScreen(transaction: txn),
      ),
    );
  }

  @override
  State<TransactionReceiptScreen> createState() =>
      _TransactionReceiptScreenState();
}

String _formatNum(num? val) {
  if (val == null) return '-';
  if (val % 1 == 0) return val.toInt().toString();
  return val.toString().replaceAll(RegExp(r'([.]*0)(?!.*\d)'), '');
}

class _TransactionReceiptScreenState extends State<TransactionReceiptScreen> {
  late Transaction transaction;
  bool _loadingItems = true;
  Map<int, double> _productBalances = {};

  // Pre-cached assets for fast PDF generation
  pw.MemoryImage? _cachedLogoImage;

  @override
  void initState() {
    super.initState();
    transaction = widget.transaction;
    _initData();
  }

  Future<void> _initData() async {
    try {
      final logoBytes = await rootBundle.load('assets/images/clogo.png');
      _cachedLogoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('[Receipt] Logo load error: $e');
    }
    await _loadFullTransaction();
  }

  Future<void> _loadFullTransaction() async {
    if (transaction.id != null) {
      try {
        final fullTxn =
            await TransactionService.instance.getById(transaction.id!);
        if (mounted) {
          setState(() {
            transaction = fullTxn;
            _loadingItems = false;
          });
        }
      } catch (e) {
        debugPrint('[Receipt] Failed to load full transaction: $e');
      }
    }

    // If no id or fetch failed, use what we have
    await _loadProductBalances();
    if (!mounted) return;
    setState(() => _loadingItems = false);
  }

  Future<void> _loadProductBalances() async {
    final balances = <int, double>{};
    for (final item in transaction.items) {
      if (item.productId != null && !balances.containsKey(item.productId)) {
        try {
          final product = await ProductService.instance.getById(item.productId!);
          if (product != null) {
            balances[item.productId!] = product.quantity.toDouble();
          }
        } catch (_) {}
      }
    }
    _productBalances = balances;
  }

  Future<void> _onEdit() async {
    if (transaction.isPendingSync) {
      NotificationBanner.show(
        context,
        'This transaction hasn\'t synced yet — it can\'t be edited until it\'s online.',
        tone: NotificationTone.warning,
      );
      return;
    }

    try {
      final fullTxn = transaction.id != null
          ? await TransactionService.instance.getById(transaction.id!)
          : transaction;
      if (!mounted) return;

      final updated = await AddTransactionScreen.showEdit(context, fullTxn);
      if (updated == true && mounted) {
        setState(() {
          _loadingItems = true;
        });
        await _loadFullTransaction();
      }
    } catch (e) {
      if (!mounted) return;
      NotificationBanner.show(
        context,
        'Failed to load transaction for editing: $e',
        tone: NotificationTone.error,
      );
    }
  }

  Future<Uint8List> _buildPdfBytes(PdfPageFormat format) async {
    final pdf = pw.Document();
    final isInbound = transaction.type.toLowerCase() == 'receive' ||
        transaction.type.toLowerCase() == 'inbound';
    final dateStr = transaction.createdAt != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(transaction.createdAt!)
        : 'N/A';

    final headers = ['#', 'Product Name', 'Quantity', 'Balance'];
    List<List<String>> dataRows;

    if (transaction.items.isNotEmpty) {
      dataRows = transaction.items.asMap().entries.map((entry) {
        final idx = entry.key + 1;
        final item = entry.value;
        final bal = (item.productId != null && _productBalances.containsKey(item.productId))
            ? _formatNum(_productBalances[item.productId])
            : '-';
        return [
          '$idx',
          item.productName.isNotEmpty ? item.productName : 'Item #$idx',
          item.formattedQuantity,
          bal,
        ];
      }).toList();
    } else {
      dataRows = [
        ['1', 'General Stock', transaction.formattedTotalItems, '-']
      ];
    }

    final logoImage = _cachedLogoImage;

    final String creatorName = (transaction.createdByName != null &&
            transaction.createdByName!.isNotEmpty &&
            transaction.createdByName != 'System User' &&
            transaction.createdByName != 'User')
        ? transaction.createdByName!
        : (AuthService.instance.displayName.isNotEmpty &&
                AuthService.instance.displayName != 'User'
            ? AuthService.instance.displayName
            : 'Admin User');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
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
                        pw.Image(logoImage, width: 42, height: 42),
                        pw.SizedBox(width: 10),
                      ],
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Celis Brothers Hardware',
                            style: const pw.TextStyle(
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red800,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Inventory Management System - Official Stock Voucher',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        transaction.billNo,
                        style: const pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey900,
                        ),
                      ),
                      pw.Text(
                        'Date: $dateStr',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
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
                pw.Text(
                  'Transaction Type: ${isInbound ? "RECEIVE" : "RELEASE"}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: isInbound ? PdfColors.green800 : PdfColors.red800,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Created By: $creatorName',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            if (transaction.remarks != null &&
                transaction.remarks!.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text(
                'Remarks: ${transaction.remarks}',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: dataRows,
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerStyle: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            pw.SizedBox(height: 20),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total Items: ${transaction.totalItems}',
                style: const pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> _printOrDownload(BuildContext context) async {
    await PdfPreviewScreen.navigateTo(
      context,
      title: 'Stock Voucher — ${transaction.billNo}',
      buildPdf: _buildPdfBytes,
      fileName: 'Voucher_${transaction.billNo.replaceAll(" ", "_")}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isInbound = transaction.type.toLowerCase() == 'receive' ||
        transaction.type.toLowerCase() == 'inbound';
    final dateStr = transaction.createdAt != null
        ? DateFormat('MMM dd, yyyy — hh:mm a').format(transaction.createdAt!)
        : 'N/A';

    final String creatorName = (transaction.createdByName != null &&
            transaction.createdByName!.isNotEmpty &&
            transaction.createdByName != 'System User' &&
            transaction.createdByName != 'User')
        ? transaction.createdByName!
        : (AuthService.instance.displayName.isNotEmpty &&
                AuthService.instance.displayName != 'User'
            ? AuthService.instance.displayName
            : 'Admin User');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Stock Voucher — ${transaction.billNo}',
            style: AppTextStyles.h3),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: _onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: PrimaryButton(
              label: 'Print / Download PDF',
              icon: Icons.print_rounded,
              onPressed: () => _printOrDownload(context),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final padding = compact ? 12.0 : 32.0;

          return SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                padding: EdgeInsets.all(compact ? 16 : 36),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    if (compact) ...[
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Image.asset('assets/images/clogo.png'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Celis Brothers Hardware',
                                    style: AppTextStyles.h2.copyWith(fontSize: 17)),
                                const SizedBox(height: 2),
                                Text('Official Voucher',
                                    style: AppTextStyles.caption.copyWith(fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(transaction.billNo,
                              style: AppTextStyles.mono.copyWith(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          StatusBadge(
                            label: isInbound ? '+ RECEIVE' : '- RELEASE',
                            tone: isInbound ? BadgeTone.success : BadgeTone.danger,
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.asset('assets/images/clogo.png'),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Celis Brothers Hardware',
                                    style: AppTextStyles.h1.copyWith(fontSize: 24)),
                                const SizedBox(height: 2),
                                Text('Inventory Management System — Official Voucher',
                                    style: AppTextStyles.caption.copyWith(fontSize: 13)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(transaction.billNo,
                                  style: AppTextStyles.mono.copyWith(
                                      fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 4),
                              StatusBadge(
                                label: isInbound ? '+ RECEIVE' : '- RELEASE',
                                tone: isInbound ? BadgeTone.success : BadgeTone.danger,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 20),

                    // Details Grid
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Date & Time', style: AppTextStyles.label),
                              const SizedBox(height: 4),
                              Text(dateStr, style: AppTextStyles.bodyMedium),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Created By', style: AppTextStyles.label),
                              const SizedBox(height: 4),
                              Text(creatorName, style: AppTextStyles.bodyMedium),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (transaction.remarks != null &&
                        transaction.remarks!.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Remarks / Notes', style: AppTextStyles.label),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(transaction.remarks!, style: AppTextStyles.body),
                      ),
                    ],

                    const SizedBox(height: 24),
                    Text('Items Summary', style: AppTextStyles.h3),
                    const SizedBox(height: 12),

                    // Items Table / List
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          if (!compact) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: const BoxDecoration(
                                color: AppColors.background,
                                borderRadius:
                                    BorderRadius.vertical(top: Radius.circular(9)),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                      width: 40,
                                      child: Text('#', style: AppTextStyles.label)),
                                  Expanded(
                                      child: Text('PRODUCT NAME',
                                          style: AppTextStyles.label)),
                                  SizedBox(
                                      width: 80,
                                      child: Text('QTY',
                                          textAlign: TextAlign.right,
                                          style: AppTextStyles.label)),
                                  SizedBox(
                                      width: 80,
                                      child: Text('BALANCE',
                                          textAlign: TextAlign.right,
                                          style: AppTextStyles.label)),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: AppColors.border),
                          ],
                          if (_loadingItems)
                            const Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          else if (transaction.items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Center(
                                child: Text('No itemized details recorded.',
                                    style: AppTextStyles.body),
                              ),
                            )
                          else
                            ...transaction.items.asMap().entries.map((entry) {
                              final idx = entry.key + 1;
                              final item = entry.value;

                              if (compact) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                        bottom: BorderSide(color: AppColors.divider)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Product name in full — no truncation
                                      Text(
                                        '$idx. ${item.productName}',
                                        style: AppTextStyles.bodyMedium.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.primarySoft,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Qty: ${item.formattedQuantity}',
                                              style: AppTextStyles.caption.copyWith(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            'Balance: ${(item.productId != null && _productBalances.containsKey(item.productId)) ? _formatNum(_productBalances[item.productId]) : '-'}',
                                            style: AppTextStyles.caption.copyWith(
                                              color: AppColors.textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: const BoxDecoration(
                                  border: Border(
                                      bottom: BorderSide(color: AppColors.divider)),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                        width: 40,
                                        child: Text('$idx',
                                            style: AppTextStyles.mono)),
                                    Expanded(
                                        child: Text(item.productName,
                                            style: AppTextStyles.bodyMedium)),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        item.formattedQuantity,
                                        textAlign: TextAlign.right,
                                        style: AppTextStyles.bodyLarge
                                            .copyWith(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        (item.productId != null && _productBalances.containsKey(item.productId))
                                            ? _formatNum(_productBalances[item.productId])
                                            : '-',
                                        textAlign: TextAlign.right,
                                        style: AppTextStyles.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Footer Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text('Official CBHIMS Stock Movement Record',
                              style: AppTextStyles.caption,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Total: ${transaction.formattedTotalItems}',
                          style:
                              AppTextStyles.h3.copyWith(color: AppColors.primary, fontSize: compact ? 16 : 18),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
