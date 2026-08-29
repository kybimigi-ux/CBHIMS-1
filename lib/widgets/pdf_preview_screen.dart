import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';

/// Interactive, zoomable in-app PDF preview screen that enables users to
/// pinch-to-zoom, pan, print, and share/download PDF reports and vouchers.
///
/// Print/share actions are surfaced in the custom AppBar (not the
/// PdfPreview package's internal toolbar) so they render consistently
/// across all screen sizes and match the app's own styling.
class PdfPreviewScreen extends StatefulWidget {
  final String title;
  final Future<Uint8List> Function(PdfPageFormat format) buildPdf;
  final String fileName;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.buildPdf,
    required this.fileName,
  });

  static Future<void> navigateTo(
    BuildContext context, {
    required String title,
    required Future<Uint8List> Function(PdfPageFormat format) buildPdf,
    required String fileName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: title,
          buildPdf: buildPdf,
          fileName: fileName,
        ),
      ),
    );
  }

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  bool _isPrinting = false;
  bool _isSharing = false;

  Future<void> _onPrint() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      await Printing.layoutPdf(
        onLayout: widget.buildPdf,
        name: widget.fileName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to print: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _onShare() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final bytes = await widget.buildPdf(PdfPageFormat.a4);
      await Printing.sharePdf(
        bytes: bytes,
        filename: widget.fileName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: AppTextStyles.h3),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isPrinting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.print_outlined),
            tooltip: 'Print',
            onPressed: _isPrinting ? null : _onPrint,
          ),
          IconButton(
            icon: _isSharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: _isSharing ? null : _onShare,
          ),
          const SizedBox(width: 8),
        ],
      ),
      backgroundColor: AppColors.background,
      body: PdfPreview(
        build: widget.buildPdf,
        pdfFileName: widget.fileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        useActions: false, // internal toolbar hidden — using our own AppBar actions above
        maxPageWidth: 900,
        scrollViewDecoration: const BoxDecoration(color: AppColors.background),
        loadingWidget: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    );
  }
}