import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Shared rendering widgets for the "مورد×عميل" combined statement —
/// used by both SupplierStatementPage and CustomerStatementPage (mobile)
/// so the merged-ledger UI is built once, not duplicated per entity side.
/// Mirrors the web's CombinedStatementBanner.tsx one-to-one.

double asNum(dynamic v) => v == null ? 0.0 : (v as num).toDouble();

class StatementSectionTitle extends StatelessWidget {
  final String text;
  const StatementSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );
}

class StatementBalanceCard extends StatelessWidget {
  final String label;
  final double value;
  final bool positiveIsBad;
  const StatementBalanceCard(
      {super.key, required this.label, required this.value, required this.positiveIsBad});

  @override
  Widget build(BuildContext context) {
    final bad = positiveIsBad ? value > 0 : value < 0;
    final color = value == 0 ? AppTheme.textMuted : (bad ? AppTheme.danger : AppTheme.secondary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            Text(value.toStringAsFixed(2),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

/// "مورد×عميل" combined ledger — badge, net-balance card, then the two
/// sections (ما أخذه مني / ما أخذته منه), each a compact transaction list.
/// Rendered identically regardless of whether the caller is the supplier
/// detail screen or the customer detail screen — same `combined` JSON
/// block, same widget, so the two entry points can never visually drift.
class CombinedStatementSection extends StatelessWidget {
  final Map<String, dynamic> combined;
  const CombinedStatementSection({super.key, required this.combined});

  @override
  Widget build(BuildContext context) {
    final net = combined['net'] as Map<String, dynamic>? ?? {};
    final direction = net['direction'] as String? ?? '';
    final label = net['label'] as String? ?? '';
    final isDebtor = direction == 'مدين'; // they owe us
    final isCreditor = direction == 'دائن'; // we owe them
    final color = isDebtor ? AppTheme.secondary : (isCreditor ? AppTheme.danger : AppTheme.textMuted);

    final asCustomer = combined['as_customer'] as Map<String, dynamic>? ?? {};
    final asSupplier = combined['as_supplier'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: AppTheme.primary.withValues(alpha: 0.06),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.people_alt_outlined, color: AppTheme.primary, size: 18),
                SizedBox(width: 8),
                Text('مورد×عميل', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  isDebtor
                      ? Icons.arrow_circle_down_outlined
                      : isCreditor
                          ? Icons.arrow_circle_up_outlined
                          : Icons.balance_outlined,
                  color: color,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
                      const SizedBox(height: 4),
                      Text(
                        'كعميل: ${asNum(net['customer_owes_us']).toStringAsFixed(2)} — '
                        'كمورد: ${asNum(net['we_owe_supplier']).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        StatementSectionTitle(asCustomer['label'] as String? ?? 'ما أخذه مني (كعميل)'),
        StatementTransactionsList(
          transactions: (asCustomer['transactions'] as List? ?? []).cast<Map<String, dynamic>>(),
          compact: true,
        ),
        const SizedBox(height: 12),
        StatementSectionTitle(asSupplier['label'] as String? ?? 'ما أخذته منه (كمورد)'),
        StatementTransactionsList(
          transactions: (asSupplier['transactions'] as List? ?? []).cast<Map<String, dynamic>>(),
          compact: true,
        ),
      ],
    );
  }
}

/// Generic transaction list — deliberately shape-agnostic (customer ledger
/// rows use invoice_number/items_summary, supplier ledger rows use
/// ref_number/notes) since this one widget renders both, mirroring the web
/// CombinedStatementBanner's MiniLedger.
class StatementTransactionsList extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final bool compact;
  const StatementTransactionsList({super.key, required this.transactions, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('لا توجد حركات', style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: transactions.map((t) {
          final debit = asNum(t['debit']);
          final credit = asNum(t['credit']);
          final ref = (t['invoice_number'] ?? t['ref_number']) as String?;
          return ListTile(
            dense: compact,
            title: Text(t['description'] as String? ?? '', style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              [t['date'] as String? ?? '', if (ref != null) ref].join(' · '),
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (debit > 0)
                  Text('+${debit.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold, fontSize: 12)),
                if (credit > 0)
                  Text('-${credit.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
