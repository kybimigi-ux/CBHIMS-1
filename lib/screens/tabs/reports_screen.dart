import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/section_card.dart';
import '../dialogs_screen/report_detail_dialog.dart';

class ReportTemplateItem {
  final String title;
  final String description;
  final String icon;
  final ReportType type;

  const ReportTemplateItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
  });
}

const List<ReportTemplateItem> reportTemplates = [
  ReportTemplateItem(
    title: 'Inventory Valuation Report',
    description: 'Current stock summary across all active inventory items.',
    icon: '📦',
    type: ReportType.inventoryValuation,
  ),
  ReportTemplateItem(
    title: 'Specific Items Report',
    description: 'Custom report filtered by specific searched items, brands, or keywords.',
    icon: '🔍',
    type: ReportType.specificItems,
  ),
  ReportTemplateItem(
    title: 'Low Stock Summary',
    description: 'Items at or below their reorder point requiring attention.',
    icon: '⚠️',
    type: ReportType.lowStockSummary,
  ),
  ReportTemplateItem(
    title: 'Stock Movement Report',
    description: 'Detailed log of inbound and outbound transactions.',
    icon: '🔄',
    type: ReportType.transactionMovement,
  ),
];

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  void _openReport(BuildContext context, ReportTemplateItem template) {
    ReportDetailDialog.show(
      context,
      reportType: template.type,
      reportTitle: template.title,
      reportDescription: template.description,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 600;
    final horizontalPadding = compact ? 16.0 : 32.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 28, horizontalPadding, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            title: 'Reports',
            subtitle: 'Generate, filter, and export official warehouse reports for STOKADO.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildQuickExportBanner(context, compact),
          const SizedBox(height: AppSpacing.lg),
          Text('Available Report Templates', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              int cols = 1;
              double aspectRatio = 1.35;
              if (constraints.maxWidth > 1100) {
                cols = 3;
                aspectRatio = 1.6;
              } else if (constraints.maxWidth > 700) {
                cols = 2;
                aspectRatio = 1.5;
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reportTemplates.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: aspectRatio,
                ),
                itemBuilder: (context, i) => _ReportCard(
                  report: reportTemplates[i],
                  onOpen: () => _openReport(context, reportTemplates[i]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickExportBanner(BuildContext context, bool compact) {
    if (compact) {
      return SectionCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf_outlined,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Official Branded Reports',
                      style: AppTextStyles.h3.copyWith(fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'All exports include the STOKADO header, customizable date range, PDF print output, and CSV download.',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'View Inventory Report',
                icon: Icons.analytics_outlined,
                onPressed: () => _openReport(context, reportTemplates[0]),
              ),
            ),
          ],
        ),
      );
    }

    return SectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Generate Official Branded Reports', style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text(
                  'All exports include the STOKADO header, customizable date range, PDF print output, and CSV download.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          PrimaryButton(
            label: 'View Inventory Report',
            icon: Icons.analytics_outlined,
            onPressed: () => _openReport(context, reportTemplates[0]),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ReportTemplateItem report;
  final VoidCallback onOpen;

  const _ReportCard({required this.report, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(report.icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(report.title,
                    style: AppTextStyles.bodyMedium,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              report.description,
              style: AppTextStyles.caption,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Generate & Export',
              icon: Icons.arrow_forward_rounded,
              onPressed: onOpen,
            ),
          ),
        ],
      ),
    );
  }
}
