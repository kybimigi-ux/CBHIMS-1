import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';

/// Interactive, zoomable in-app PDF preview screen that enables users to
/// pinch-to-zoom, pan, print, and share/download PDF reports and vouchers.
class PdfPreviewScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: AppTextStyles.h3),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColors.background,
      body: PdfPreview(
        build: buildPdf,
        pdfFileName: fileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        maxPageWidth: 900,
        scrollViewDecoration: const BoxDecoration(color: AppColors.background),
        loadingWidget: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    );
  }
}
