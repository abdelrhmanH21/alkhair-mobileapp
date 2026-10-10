import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/security/sensitive_reveal_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/masked_amount.dart';
import 'price_variance_dashboard_section.dart';

/// Body of the free-pricing delegate's "تقرير التحميلات" tab in التقارير.
/// Nothing is fetched or built until the shared SensitiveRevealController is
/// unlocked (biometric / device PIN); while locked it shows a bland "protected"
/// placeholder. Once unlocked it hosts the existing
/// [PriceVarianceDashboardSection] (balance + per-loading drill-down into
/// PriceVarianceLoadingDetailPage) unchanged. The section is removed from the
/// tree again on re-lock, so its data isn't retained in memory either.
class PriceVarianceReportTab extends StatelessWidget {
  /// Overridable for tests; defaults to the app-wide shared instance.
  final SensitiveRevealController? revealController;
  const PriceVarianceReportTab({super.key, this.revealController});

  @override
  Widget build(BuildContext context) {
    final reveal = revealController ?? sl<SensitiveRevealController>();
    return ListenableBuilder(
      listenable: reveal,
      builder: (context, _) {
        if (reveal.isRevealed) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: PriceVarianceDashboardSection(revealController: reveal),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 40, color: Colors.grey.shade500),
                const SizedBox(height: 12),
                const Text('هذا التقرير محمي', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('تحقق من هويتك لعرضه.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                const SizedBox(height: 16),
                reveal.isAuthenticating
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : OutlinedButton(
                        key: const ValueKey('report-unlock-button'),
                        onPressed: () => requestRevealWithFeedback(context, reveal),
                        child: const Text('عرض'),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }
}
