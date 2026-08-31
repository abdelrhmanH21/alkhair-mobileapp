import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';

/// كشف حساب مورد — reachable by tapping a supplier row in
/// AdminCustomersSuppliersPage's الموردون tab. Hits the same
/// GET /reports/supplier-statement endpoint the web SupplierStatementPage/
/// CustomerStatementPage use (ReportController::supplierStatement()) — when
/// the supplier is مورد×عميل-linked, the response's `combined` block is
/// rendered as a merged ledger (ما أخذه مني / ما أخذته منه + net line),
/// exactly mirroring the web's CombinedStatementBanner. No merge logic is
/// duplicated here — the backend computes everything, this page just
/// displays it.
class SupplierStatementPage extends StatefulWidget {
  final int supplierId;
  final String supplierName;
  const SupplierStatementPage({super.key, required this.supplierId, required this.supplierName});

  @override
  State<SupplierStatementPage> createState() => _SupplierStatementPageState();
}

class _SupplierStatementPageState extends State<SupplierStatementPage> {
  final _remote = sl<AdminRemoteDataSource>();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _remote.fetchSupplierStatement(widget.supplierId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'فشل تحميل كشف الحساب.';
      });
    }
  }

  static double _num(dynamic v) => v == null ? 0.0 : (v as num).toDouble();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('كشف حساب — ${widget.supplierName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final data = _data!;
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final combined = data['combined'] as Map<String, dynamic>?;
    final transactions = (data['transactions'] as List? ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _BalanceCard(
            label: 'الرصيد المستحق للمورد',
            value: _num(summary['current_balance']),
            positiveIsBad: true, // owed BY us TO the supplier
          ),
          const SizedBox(height: 12),

          if (combined != null) ...[
            _CombinedSection(combined: combined),
            const SizedBox(height: 12),
          ] else ...[
            const _SectionTitle('تفاصيل الحركات'),
            _TransactionsList(transactions: transactions),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );
}

class _BalanceCard extends StatelessWidget {
  final String label;
  final double value;
  final bool positiveIsBad;
  const _BalanceCard({required this.label, required this.value, required this.positiveIsBad});

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
class _CombinedSection extends StatelessWidget {
  final Map<String, dynamic> combined;
  const _CombinedSection({required this.combined});

  static double _num(dynamic v) => v == null ? 0.0 : (v as num).toDouble();

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
                        'كعميل: ${_num(net['customer_owes_us']).toStringAsFixed(2)} — '
                        'كمورد: ${_num(net['we_owe_supplier']).toStringAsFixed(2)}',
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
        _SectionTitle(asCustomer['label'] as String? ?? 'ما أخذه مني (كعميل)'),
        _TransactionsList(
          transactions: (asCustomer['transactions'] as List? ?? []).cast<Map<String, dynamic>>(),
          compact: true,
        ),
        const SizedBox(height: 12),
        _SectionTitle(asSupplier['label'] as String? ?? 'ما أخذته منه (كمورد)'),
        _TransactionsList(
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
class _TransactionsList extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final bool compact;
  const _TransactionsList({required this.transactions, this.compact = false});

  static double _num(dynamic v) => v == null ? 0.0 : (v as num).toDouble();

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
          final debit = _num(t['debit']);
          final credit = _num(t['credit']);
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
