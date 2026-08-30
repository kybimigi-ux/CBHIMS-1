import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/product.dart';
import '../../models/transaction.dart';
import '../../services/product_service.dart';
import '../../services/transaction_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/pdf_preview_screen.dart';
import '../../widgets/status_badge.dart';

enum ReportType {
  inventoryValuation,
  specificItems,
  lowStockSummary,
  transactionMovement,
}

class ReportDetailDialog extends StatefulWidget {
  final ReportType reportType;
  final String reportTitle;
  final String reportDescription;

  const ReportDetailDialog({
    super.key,
    required this.reportType,
    required this.reportTitle,
    required this.reportDescription,
  });

  static Future<void> show(
    BuildContext context, {
    required ReportType reportType,
    required String reportTitle,
    required String reportDescription,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ReportDetailDialog(
        reportType: reportType,
        reportTitle: reportTitle,
        reportDescription: reportDescription,
      ),
    );
  }

  @override
  State<ReportDetailDialog> createState() => _ReportDetailDialogState();
}

class _ReportDetailDialogState extends State<ReportDetailDialog> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  List<Product> _products = [];
  List<Transaction> _transactions = [];
  bool _loading = true;
  String? _error;

  final TextEditingController _itemSearchController = TextEditingController();
  final Set<int> _selectedProductIds = <int>{};

  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  @override
  void dispose() {
    _itemSearchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Brand & Keyword-Aware Grouping & Natural Sorting
  // ---------------------------------------------------------------------------
  static final Set<String> _ignoredTokens = {
    'and', 'or', 'with', 'the', 'for', 'in', 'of', 'no', 'x',
    'mm', 'cm', 'm', 'inch', 'kg', 'g', 'lbs', 'pc', 'pcs',
    'box', 'roll', 'bag', 'bundle', 'set', 'meter', 'feet', 'ft',
    'heavy', 'duty', 'standard', 'original', 'class', 'type',
  };

  static final Set<String> _genericCategoryTokens = {
    'pipe', 'pipes', 'fitting', 'fittings', 'elbow', 'tee', 'coupling',
    'adapter', 'reducer', 'valve', 'valves', 'cement', 'steel', 'bar',
    'bars', 'wire', 'wires', 'nail', 'nails', 'screw', 'screws', 'paint',
    'paints', 'board', 'boards', 'plywood', 'hose', 'tape', 'lock', 'locks',
    'faucet', 'faucets', 'switch', 'switches', 'plate', 'plates', 'tube',
    'tubes', 'rod', 'rods', 'sheet', 'sheets', 'tile', 'tiles', 'sand',
    'gravel', 'lumber', 'wood', 'bulb', 'light', 'handle', 'hinge', 'hinges',
  };

  static void _sortProductsByBrandAndName(List<Product> list) {
    if (list.length <= 1) return;

    // 1. Identify common words across the list
    final Map<String, int> wordCounts = {};
    for (final p in list) {
      final seenInProduct = <String>{};
      final tokens = p.productName
          .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
          .split(RegExp(r'\s+'));

      for (final raw in tokens) {
        final token = raw.trim().toLowerCase();
        if (token.length < 3 ||
            int.tryParse(token) != null ||
            _ignoredTokens.contains(token)) {
          continue;
        }
        seenInProduct.add(token);
      }

      for (final t in seenInProduct) {
        wordCounts[t] = (wordCounts[t] ?? 0) + 1;
      }
    }

    final brandKeywords = <String>{};
    final categoryKeywords = <String>{};

    wordCounts.forEach((word, count) {
      if (count >= 2) {
        if (_genericCategoryTokens.contains(word)) {
          categoryKeywords.add(word);
        } else {
          brandKeywords.add(word);
        }
      }
    });

    // 2. Map each product to its cluster key
    final Map<Product, String> groupKeyMap = {};
    for (final p in list) {
      final tokens = p.productName
          .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
          .split(RegExp(r'\s+'))
          .map((t) => t.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toList();

      String? key;
      // High priority: brand keyword appearing in multiple products (e.g. Atlanta, Mabuhay)
      for (final token in tokens) {
        if (brandKeywords.contains(token)) {
          key = token;
          break;
        }
      }

      // Medium priority: category keyword
      if (key == null) {
        for (final token in tokens) {
          if (categoryKeywords.contains(token)) {
            key = token;
            break;
          }
        }
      }

      // Low priority: first significant word
      if (key == null) {
        for (final token in tokens) {
          if (token.length >= 3 &&
              int.tryParse(token) == null &&
              !_ignoredTokens.contains(token)) {
            key = token;
            break;
          }
        }
      }

      groupKeyMap[p] = key ?? (tokens.isNotEmpty ? tokens.first : p.productName.toLowerCase().trim());
    }

    // 3. Sort by group key, then by full product name naturally
    list.sort((a, b) {
      final keyA = groupKeyMap[a]!;
      final keyB = groupKeyMap[b]!;

      final keyComp = _naturalCompare(keyA, keyB);
      if (keyComp != 0) return keyComp;

      return _naturalCompare(a.productName, b.productName);
    });
  }

  static int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+)|(\D+)');
    final matchesA = regExp
        .allMatches(a.toLowerCase().trim())
        .map((m) => m.group(0)!)
        .toList();
    final matchesB = regExp
        .allMatches(b.toLowerCase().trim())
        .map((m) => m.group(0)!)
        .toList();

    final minLen =
        matchesA.length < matchesB.length ? matchesA.length : matchesB.length;
    for (int i = 0; i < minLen; i++) {
      final partA = matchesA[i];
      final partB = matchesB[i];

      final numA = int.tryParse(partA);
      final numB = int.tryParse(partB);

      if (numA != null && numB != null) {
        final diff = numA.compareTo(numB);
        if (diff != 0) return diff;
      } else {
        final diff = partA.compareTo(partB);
        if (diff != 0) return diff;
      }
    }
    return matchesA.length.compareTo(matchesB.length);
  }

  Future<void> _loadReportData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (widget.reportType == ReportType.transactionMovement) {
        final txns = await TransactionService.instance.getAll();
        if (!mounted) return;
        setState(() {
          _transactions = txns;
          _loading = false;
        });
      } else {
        final products = await ProductService.instance.getAll();
        _sortProductsByBrandAndName(products);
        if (!mounted) return;
        setState(() {
          _products = products;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  // Displayed products in specific items selector based on live search
  List<Product> get _displayedSpecificItems {
    final query = _itemSearchController.text.trim().toLowerCase();
    final list = query.isEmpty
        ? List<Product>.from(_products)
        : _products
            .where((p) => p.productName.toLowerCase().contains(query))
            .toList();
    _sortProductsByBrandAndName(list);
    return list;
  }

  // Selected products for export/report
  List<Product> get _filteredProducts {
    if (widget.reportType == ReportType.lowStockSummary) {
      final list = _products.where((p) => p.quantity <= 10).toList();
      _sortProductsByBrandAndName(list);
      return list;
    }
    if (widget.reportType == ReportType.specificItems) {
      final list = _products
          .where((p) => p.id != null && _selectedProductIds.contains(p.id))
          .toList();
      _sortProductsByBrandAndName(list);
      return list;
    }
    final list = List<Product>.from(_products);
    _sortProductsByBrandAndName(list);
    return list;
  }

  List<Transaction> get _filteredTransactions {
    return _transactions.where((t) {
      if (t.createdAt == null) return true;
      final d = t.createdAt!;
      final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
      final end =
          DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
      return d.isAfter(start.subtract(const Duration(seconds: 1))) &&
          d.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();
  }

  List<Map<String, dynamic>> get _computedTransactionRows {
    final sorted = List<Transaction>.from(_transactions)
      ..sort((a, b) => (a.createdAt ?? DateTime(1970))
          .compareTo(b.createdAt ?? DateTime(1970)));

    double running = 0.0;
    final Map<dynamic, double> balanceMap = {};
    for (int i = 0; i < sorted.length; i++) {
      final t = sorted[i];
      final isReceive = t.type.toLowerCase() == 'receive' ||
          t.type.toLowerCase() == 'inbound' ||
          t.type.toLowerCase() == 'purchase';
      if (isReceive) {
        running += t.totalItems;
      } else {
        running -= t.totalItems;
      }
      final key = t.id ?? t.billNo;
      balanceMap[key] = running;
    }

    final filtered = _filteredTransactions;
    return filtered.map((t) {
      final key = t.id ?? t.billNo;
      final bal = balanceMap[key] ?? 0.0;
      return {
        'transaction': t,
        'balance': bal,
      };
    }).toList();
  }

  void _selectAllFiltered() {
    setState(() {
      for (final p in _displayedSpecificItems) {
        if (p.id != null) {
          _selectedProductIds.add(p.id!);
        }
      }
    });
  }

  void _deselectAllFiltered() {
    setState(() {
      for (final p in _displayedSpecificItems) {
        if (p.id != null) {
          _selectedProductIds.remove(p.id);
        }
      }
    });
  }

  void _clearAllSelections() {
    setState(() {
      _selectedProductIds.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // PDF Document Builder
  // ---------------------------------------------------------------------------
  Future<Uint8List> _buildPdfBytes(PdfPageFormat format) async {
    final pdf = pw.Document();

    final dateRangeStr =
        '${_dateFormat.format(_startDate)} - ${_dateFormat.format(_endDate)}';
    final generatedAtStr =
        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    final subtitleFilters = widget.reportType == ReportType.specificItems
        ? 'Specific Items Report (${_filteredProducts.length} selected items)'
        : 'Date Range: $dateRangeStr';

    final List<String> headers;
    final List<List<String>> dataRows;

    if (widget.reportType == ReportType.transactionMovement) {
      headers = [
        'Bill No.',
        'Type',
        'Total Items',
        'Created By',
      ];
      dataRows = _computedTransactionRows.map((row) {
        final t = row['transaction'] as Transaction;
        final dStr =
            t.createdAt != null ? _dateFormat.format(t.createdAt!) : 'N/A';
        return [
          '${t.billNo}\n$dStr',
          t.type.toUpperCase(),
          t.formattedTotalItems,
          t.createdByName ?? 'User',
        ];
      }).toList();
    } else {
      headers = [
        'Product Name',
        'Quantity',
        'Unit',
        'Stock Status',
      ];
      dataRows = _filteredProducts.map((p) {
        final statusStr = p.quantity <= 0
            ? 'Out of stock'
            : (p.quantity <= 10 ? 'Low stock' : 'Healthy');
        return [
          p.productName,
          p.formattedQuantity,
          p.unit,
          statusStr,
        ];
      }).toList();
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
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
                        'Inventory Management System - Official Report',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700),
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
            pw.Text(widget.reportTitle,
                style: const pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(subtitleFilters,
                style:
                    const pw.TextStyle(fontSize: 11, color: PdfColors.grey800)),
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
          ];
        },
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------------
  // PDF Preview (zoomable) + Export
  // ---------------------------------------------------------------------------
  Future<void> _openPdfPreview() async {
    if (widget.reportType == ReportType.specificItems &&
        _selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Please check at least one product to generate the report.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (!mounted) return;
    await PdfPreviewScreen.navigateTo(
      context,
      title: widget.reportTitle,
      buildPdf: _buildPdfBytes,
      fileName: '${widget.reportTitle.replaceAll(" ", "_")}.pdf',
    );
  }

  // ---------------------------------------------------------------------------
  // CSV Generation & Export
  // ---------------------------------------------------------------------------
  Future<void> _exportCsv() async {
    if (widget.reportType == ReportType.specificItems &&
        _selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Please check at least one product to generate the report.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final StringBuffer csvBuffer = StringBuffer();

    // Title & Date Header
    csvBuffer.writeln('"Celis Brothers Hardware - ${widget.reportTitle}"');
    if (widget.reportType == ReportType.specificItems) {
      csvBuffer.writeln(
          '"Specific Items Report - ${_filteredProducts.length} Selected Items"');
    } else {
      csvBuffer.writeln(
          '"Date Range: ${_dateFormat.format(_startDate)} to ${_dateFormat.format(_endDate)}"');
    }
    csvBuffer.writeln();

    if (widget.reportType == ReportType.transactionMovement) {
      csvBuffer.writeln('"Bill No.","Type","Total Items","Created By","Date"');
      for (final row in _computedTransactionRows) {
        final t = row['transaction'] as Transaction;
        final dStr =
            t.createdAt != null ? _dateFormat.format(t.createdAt!) : 'N/A';
        csvBuffer.writeln(
            '"${t.billNo}","${t.type}","${t.formattedTotalItems}","${t.createdByName ?? ''}","$dStr"');
      }
    } else {
      csvBuffer.writeln('"Product Name","Quantity","Unit","Stock Status"');
      for (final p in _filteredProducts) {
        final statusStr = p.quantity <= 0
            ? 'Out of stock'
            : (p.quantity <= 10 ? 'Low stock' : 'Healthy');
        csvBuffer.writeln(
            '"${p.productName}","${p.formattedQuantity}","${p.unit}","$statusStr"');
      }
    }

    final bytes = utf8.encode(csvBuffer.toString());
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: '${widget.reportTitle.replaceAll(" ", "_")}.csv',
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 600;
    final dialogWidth = width > 900 ? 860.0 : (compact ? width : width * 0.94);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 16)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
            maxHeight:
                compact ? MediaQuery.of(context).size.height * 0.92 : 760),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBrandedHeader(compact),
            const Divider(height: 1, color: AppColors.border),
            if (widget.reportType != ReportType.specificItems) ...[
              _buildDateRangeSelector(compact),
              const Divider(height: 1, color: AppColors.border),
            ],
            if (widget.reportType == ReportType.specificItems) ...[
              _buildSpecificItemFilter(compact),
            ],
            Expanded(child: _buildDataPreview()),
            const Divider(height: 1, color: AppColors.border),
            _buildActions(compact),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandedHeader(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 28, compact ? 14 : 20,
          compact ? 12 : 20, compact ? 12 : 16),
      child: Row(
        children: [
          Container(
            width: compact ? 38 : 48,
            height: compact ? 38 : 48,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(compact ? 8 : 12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 8 : 12),
              child: Image.asset('assets/images/clogo.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Celis Brothers Hardware',
                        style: AppTextStyles.h2
                            .copyWith(fontSize: compact ? 16 : 20),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('OFFICIAL REPORT',
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 10)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(widget.reportTitle,
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: compact ? 12 : 14)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textMuted, size: 20),
            splashRadius: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector(bool compact) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: AppColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.date_range_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('Filter Date Range',
                        style: AppTextStyles.caption
                            .copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                Text(
                  widget.reportType == ReportType.transactionMovement
                      ? '${_filteredTransactions.length} transactions'
                      : '${_filteredProducts.length} items',
                  style: AppTextStyles.caption
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _dateButton(
                      label: _dateFormat.format(_startDate),
                      onTap: _selectStartDate),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 14, color: AppColors.textMuted),
                ),
                Expanded(
                  child: _dateButton(
                      label: _dateFormat.format(_endDate),
                      onTap: _selectEndDate),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      color: AppColors.background,
      child: Row(
        children: [
          const Icon(Icons.date_range_rounded,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Text('Filter Date Range:',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          _dateButton(
              label: _dateFormat.format(_startDate), onTap: _selectStartDate),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded,
              size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          _dateButton(
              label: _dateFormat.format(_endDate), onTap: _selectEndDate),
          const Spacer(),
          Text(
            widget.reportType == ReportType.transactionMovement
                ? '${_filteredTransactions.length} transactions'
                : '${_filteredProducts.length} items',
            style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecificItemFilter(bool compact) {
    final displayed = _displayedSpecificItems;
    final allFilteredSelected = displayed.isNotEmpty &&
        displayed
            .every((p) => p.id != null && _selectedProductIds.contains(p.id));

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 42,
              child: TextField(
                controller: _itemSearchController,
                onChanged: (_) => setState(() {}),
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search product name (e.g. Atlanta, Mabuhay)...',
                  hintStyle: AppTextStyles.body
                      .copyWith(color: AppColors.textMuted, fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.primary),
                  suffixIcon: _itemSearchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () {
                            _itemSearchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: allFilteredSelected
                        ? _deselectAllFiltered
                        : _selectAllFiltered,
                    icon: Icon(
                      allFilteredSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      allFilteredSelected ? 'Deselect All' : 'Select All',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (_selectedProductIds.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _clearAllSelections,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text('Clear (${_selectedProductIds.length})',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${displayed.length} of ${_products.length} products',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _selectedProductIds.isNotEmpty
                        ? AppColors.primarySoft
                        : AppColors.neutralSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_selectedProductIds.length} checked for report',
                    style: AppTextStyles.caption.copyWith(
                      color: _selectedProductIds.isNotEmpty
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _itemSearchController,
                    onChanged: (_) => setState(() {}),
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText:
                          'Search product name or brand (e.g. Atlanta, Mabuhay)...',
                      hintStyle: AppTextStyles.body
                          .copyWith(color: AppColors.textMuted, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 20, color: AppColors.primary),
                      suffixIcon: _itemSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _itemSearchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
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
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: allFilteredSelected
                    ? _deselectAllFiltered
                    : _selectAllFiltered,
                icon: Icon(
                  allFilteredSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                label: Text(
                  allFilteredSelected ? 'Deselect All' : 'Select All Filtered',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (_selectedProductIds.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _clearAllSelections,
                  child: Text('Clear Selection',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.danger)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${displayed.length} of ${_products.length} products (sorted by name/brand)',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _selectedProductIds.isNotEmpty
                      ? AppColors.primarySoft
                      : AppColors.neutralSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_selectedProductIds.length} of ${_products.length} items checked for report',
                  style: AppTextStyles.caption.copyWith(
                    color: _selectedProductIds.isNotEmpty
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateButton({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
                child: Text(label,
                    style: AppTextStyles.bodyMedium,
                    overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_today_rounded,
                size: 13, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildDataPreview() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Failed to load report data', style: AppTextStyles.h3),
            const SizedBox(height: 6),
            Text(_error!,
                style: AppTextStyles.caption.copyWith(color: AppColors.danger)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _loadReportData, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (widget.reportType == ReportType.transactionMovement) {
      final rows = _computedTransactionRows;
      if (rows.isEmpty) {
        return Center(
          child: Text('No transactions found within selected date range.',
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 500),
            child: Table(
              border: TableBorder.all(color: AppColors.border, width: 1),
              columnWidths: const {
                0: FlexColumnWidth(2.5),
                1: FlexColumnWidth(1.3),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1.8),
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: AppColors.background),
                  children: [
                    _TableCellHeader('TRANSACTION / ITEM'),
                    _TableCellHeader('TYPE'),
                    _TableCellHeader('QTY'),
                    _TableCellHeader('DATE / USER'),
                  ],
                ),
                ...rows.map((row) {
                  final t = row['transaction'] as Transaction;
                  final inbound = t.type.toLowerCase() == 'receive' ||
                      t.type.toLowerCase() == 'inbound' ||
                      t.type.toLowerCase() == 'purchase';
                  final dStr = t.createdAt != null
                      ? _dateFormat.format(t.createdAt!)
                      : 'N/A';
                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.billNo,
                                style: AppTextStyles.bodyMedium
                                    .copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      _TableCellWidget(StatusBadge(
                          label: inbound ? 'RECEIVE' : 'RELEASE',
                          tone:
                              inbound ? BadgeTone.success : BadgeTone.danger)),
                      _TableCellText('${t.totalItems}'),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dStr, style: AppTextStyles.caption),
                            Text(t.createdByName ?? 'User',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      );
    } else if (widget.reportType == ReportType.specificItems) {
      // Interactive specific item selector with Checkboxes
      final displayed = _displayedSpecificItems;

      if (displayed.isEmpty) {
        final query = _itemSearchController.text.trim();
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.search_off_rounded,
                      color: AppColors.primary, size: 28),
                ),
                const SizedBox(height: 14),
                Text('No products match "$query"', style: AppTextStyles.h3),
                const SizedBox(height: 6),
                Text(
                  'Try searching for another keyword (e.g. Atlanta, Mabuhay, Cement, Steel).',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      }

      final allFilteredSelected = displayed.isNotEmpty &&
          displayed
              .every((p) => p.id != null && _selectedProductIds.contains(p.id));

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 540),
            child: Table(
              border: TableBorder.all(color: AppColors.border, width: 1),
              columnWidths: const {
                0: FixedColumnWidth(48),
                1: FlexColumnWidth(3.0),
                2: FlexColumnWidth(1.0),
                3: FlexColumnWidth(1.0),
                4: FlexColumnWidth(1.4),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: AppColors.background),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Center(
                        child: Checkbox(
                          value: allFilteredSelected,
                          activeColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                          onChanged: (_) {
                            if (allFilteredSelected) {
                              _deselectAllFiltered();
                            } else {
                              _selectAllFiltered();
                            }
                          },
                        ),
                      ),
                    ),
                    const _TableCellHeader('PRODUCT NAME'),
                    const _TableCellHeader('QTY'),
                    const _TableCellHeader('UNIT'),
                    const _TableCellHeader('STOCK STATUS'),
                  ],
                ),
                ...displayed.map((p) {
                  final isChecked =
                      p.id != null && _selectedProductIds.contains(p.id);
                  final tone = p.quantity <= 0
                      ? BadgeTone.danger
                      : (p.quantity <= 10
                          ? BadgeTone.warning
                          : BadgeTone.success);
                  final statusStr = p.quantity <= 0
                      ? 'Out of stock'
                      : (p.quantity <= 10 ? 'Low stock' : 'Healthy');

                  return TableRow(
                    decoration: BoxDecoration(
                      color: isChecked
                          ? AppColors.primary.withValues(alpha: 0.04)
                          : null,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Center(
                          child: Checkbox(
                            value: isChecked,
                            activeColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4)),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  if (p.id != null) {
                                    _selectedProductIds.add(p.id!);
                                  }
                                } else {
                                  _selectedProductIds.remove(p.id);
                                }
                              });
                            },
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (isChecked) {
                              _selectedProductIds.remove(p.id);
                            } else {
                              if (p.id != null) {
                                _selectedProductIds.add(p.id!);
                              }
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            p.productName,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight:
                                  isChecked ? FontWeight.bold : FontWeight.w500,
                              color: isChecked
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      _TableCellText(p.formattedQuantity),
                      _TableCellText(p.unit),
                      _TableCellWidget(
                          StatusBadge(label: statusStr, tone: tone)),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      );
    } else {
      final products = _filteredProducts;
      if (products.isEmpty) {
        return Center(
          child: Text('No products match this report criteria.',
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 480),
            child: Table(
              border: TableBorder.all(color: AppColors.border, width: 1),
              columnWidths: const {
                0: FlexColumnWidth(2.8),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1.4),
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: AppColors.background),
                  children: [
                    _TableCellHeader('PRODUCT NAME'),
                    _TableCellHeader('QTY'),
                    _TableCellHeader('UNIT'),
                    _TableCellHeader('STOCK STATUS'),
                  ],
                ),
                ...products.map((p) {
                  final tone = p.quantity <= 0
                      ? BadgeTone.danger
                      : (p.quantity <= 10
                          ? BadgeTone.warning
                          : BadgeTone.success);
                  final statusStr = p.quantity <= 0
                      ? 'Out of stock'
                      : (p.quantity <= 10 ? 'Low stock' : 'Healthy');

                  return TableRow(
                    children: [
                      _TableCellText(p.productName, isBold: true),
                      _TableCellText(p.formattedQuantity),
                      _TableCellText(p.unit),
                      _TableCellWidget(
                          StatusBadge(label: statusStr, tone: tone)),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildActions(bool compact) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: SecondaryButton(
                      label: 'Export CSV',
                      icon: Icons.table_chart_outlined,
                      onPressed: _exportCsv,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: PrimaryButton(
                      label: 'Preview / Export PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      onPressed: _openPdfPreview,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Close', style: AppTextStyles.bodyMedium),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            child: Text('Close', style: AppTextStyles.bodyMedium),
          ),
          const Spacer(),
          SecondaryButton(
            label: 'Export CSV',
            icon: Icons.table_chart_outlined,
            onPressed: _exportCsv,
          ),
          const SizedBox(width: 12),
          PrimaryButton(
            label: 'Preview / Export PDF',
            icon: Icons.picture_as_pdf_outlined,
            onPressed: _openPdfPreview,
          ),
        ],
      ),
    );
  }
}

class _TableCellHeader extends StatelessWidget {
  final String text;
  const _TableCellHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(text, style: AppTextStyles.label.copyWith(fontSize: 11)),
    );
  }
}

class _TableCellText extends StatelessWidget {
  final String text;
  final bool isBold;
  const _TableCellText(this.text, {this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        text,
        style: isBold ? AppTextStyles.bodyMedium : AppTextStyles.body,
      ),
    );
  }
}

class _TableCellWidget extends StatelessWidget {
  final Widget child;
  const _TableCellWidget(this.child);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }
}
