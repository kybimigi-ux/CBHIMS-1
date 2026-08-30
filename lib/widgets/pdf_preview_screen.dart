import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';
import 'notification_banner.dart';

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
  final TransformationController _transformationController =
      TransformationController();
  bool _isPrinting = false;
  bool _isSharing = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _handleShare() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final bytes = await widget.buildPdf(PdfPageFormat.a4);
      await Printing.sharePdf(bytes: bytes, filename: widget.fileName);
    } catch (e) {
      if (mounted) {
        NotificationBanner.show(
          context,
          'Failed to share PDF: $e',
          tone: NotificationTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _handlePrint() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => widget.buildPdf(format),
        name: widget.fileName,
      );
    } catch (e) {
      if (mounted) {
        NotificationBanner.show(
          context,
          'Failed to print PDF: $e',
          tone: NotificationTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title, style: AppTextStyles.h3),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_out_map_rounded, size: 20),
            tooltip: 'Reset Zoom',
            onPressed: _resetZoom,
          ),
          IconButton(
            icon: _isSharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.share_rounded, size: 20),
            tooltip: 'Share PDF',
            onPressed: _isSharing ? null : _handleShare,
          ),
          IconButton(
            icon: _isPrinting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.print_rounded, size: 20),
            tooltip: 'Print PDF',
            onPressed: _isPrinting ? null : _handlePrint,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 0.8,
        maxScale: 4.0,
        panEnabled: true,
        scaleEnabled: true,
        clipBehavior: Clip.none,
        child: PdfPreview(
          build: widget.buildPdf,
          pdfFileName: widget.fileName,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          useActions: false,
          allowPrinting: false,
          allowSharing: false,
          maxPageWidth: 900,
          scrollViewDecoration: const BoxDecoration(color: AppColors.background),
          pdfPreviewPageDecoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          loadingWidget: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}