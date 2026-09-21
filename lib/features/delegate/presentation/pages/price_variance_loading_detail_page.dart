import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/price_variance_models.dart';

/// One تحميلة's full price-variance breakdown — every sold line (customer,
/// product, qty, reference price, charged price, variance). Pure display:
/// all data already arrived with the summary fetch
/// (PriceVarianceDashboardSection), so this page takes it via constructor
/// rather than dispatching its own DelegateBloc event — same "page pushed
/// from a list" convention other detail pages in this app follow when they
/// have nothing new to fetch.
class PriceVarianceLoadingDetailPage extends StatelessWidget {
  final PriceVarianceLoadingModel loading;
  const PriceVarianceLoadingDetailPage({super.key, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('تحميلة ${loading.date ?? ''}')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppTheme.secondary.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('إجمالي فرق السعر', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  loading.loadingVarianceTotal.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary, fontSize: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading.lines.isEmpty
                ? const Center(
                    child: Text('لا توجد أصناف في هذه التحميلة.', style: TextStyle(color: AppTheme.textMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: loading.lines.length,
                    itemBuilder: (_, i) => _LineCard(line: loading.lines[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final PriceVarianceLineModel line;
  const _LineCard({required this.line});

  @override
  Widget build(BuildContext context) {
    final positive = line.variance >= 0;
    final color = positive ? AppTheme.secondary : AppTheme.danger;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(line.productName ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Text('${positive ? '+' : ''}${line.variance.toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 4),
            Text('العميل: ${line.customerName ?? '—'} — فاتورة ${line.invoiceNumber}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MiniStat(label: 'الكمية', value: line.quantity.toStringAsFixed(2)),
                _MiniStat(label: 'السعر المرجعي', value: line.referencePrice.toStringAsFixed(2)),
                _MiniStat(label: 'السعر المُحصّل', value: line.chargedPrice.toStringAsFixed(2)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ],
      );
}
