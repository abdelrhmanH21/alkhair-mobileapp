import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../widgets/combined_statement_widgets.dart';

/// كشف حساب تفصيلي — the customer-side counterpart of SupplierStatementPage,
/// reachable from AdminCustomersSuppliersPage's العملاء tab. Hits
/// GET /reports/customer-statement (ReportController::customerStatement()) —
/// when this customer is مورد×عميل-linked (from the supplier side), the
/// response's `combined` block renders via CombinedStatementSection, the
/// exact same shared widget SupplierStatementPage uses, so both entry
/// points for the same linked pair render an identical merged ledger.
///
/// This was the actual root cause of the "combined view only reachable
/// from the supplier side" bug on mobile: the customers tab's row only
/// ever navigated to CustomerInvoiceHistoryPage (invoice history, unaware
/// of مورد×عميل entirely) — there was no mobile screen that called
/// customer-statement at all. Added as a new icon action alongside that
/// existing tap-to-view-history behavior, not a replacement for it.
class CustomerStatementPage extends StatefulWidget {
  final int customerId;
  final String customerName;
  const CustomerStatementPage({super.key, required this.customerId, required this.customerName});

  @override
  State<CustomerStatementPage> createState() => _CustomerStatementPageState();
}

class _CustomerStatementPageState extends State<CustomerStatementPage> {
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
      final data = await _remote.fetchCustomerStatement(widget.customerId);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('كشف حساب — ${widget.customerName}')),
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
          StatementBalanceCard(
            label: 'المديونية الحالية',
            value: asNum(summary['current_balance']),
            positiveIsBad: true, // owed BY the customer TO us
          ),
          const SizedBox(height: 12),

          if (combined != null) ...[
            CombinedStatementSection(combined: combined),
            const SizedBox(height: 12),
          ] else ...[
            const StatementSectionTitle('تفاصيل الحركات'),
            StatementTransactionsList(transactions: transactions),
          ],
        ],
      ),
    );
  }
}
