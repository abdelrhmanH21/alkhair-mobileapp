import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/models/customer_invoice_history_model.dart';
import '../../domain/repositories/delegate_repository.dart';
import 'invoice_detail_page.dart';

/// سجل الفواتير السابقة لعميل معيّن — عبر كل المندوبين الذين تعاملوا معه
/// وليس فقط المندوب الحالي (تاريخ الشراء ملك للعميل لا للمندوب). المصدر:
/// GET /delegate/customers/{id}/invoices (DelegateInvoiceController::customerHistory).
///
/// تستدعي DelegateRepository مباشرة (بنفس أسلوب InvoiceDetailPage) بدلاً من
/// إطلاق أحداث عبر DelegateBloc المشترك: هذه الصفحة تُفتح عادة فوق شاشة
/// أخرى (فاتورة جديدة أو نموذج تحصيل) ما زالت تستمع لحالات نفس الـ bloc،
/// فإطلاق DelegateLoading()/DelegateFailure() هنا كان سيُظهر مؤشر تحميل أو
/// رسالة خطأ زائفة على الشاشة الأسفل.
class CustomerInvoiceHistoryPage extends StatefulWidget {
  final int customerId;
  final String customerName;
  const CustomerInvoiceHistoryPage({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  @override
  State<CustomerInvoiceHistoryPage> createState() => _CustomerInvoiceHistoryPageState();
}

class _CustomerInvoiceHistoryPageState extends State<CustomerInvoiceHistoryPage> {
  final _repo = sl<DelegateRepository>();

  CustomerInvoiceHistorySummaryModel? _summary;
  final List<CustomerInvoiceHistoryRowModel> _rows = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await _repo.getCustomerInvoiceHistory(widget.customerId);
      setState(() {
        _summary = result.summary;
        _rows
          ..clear()
          ..addAll(result.rows);
        _currentPage = result.currentPage;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _loading = false;
        _loadError = e.response?.data?['message'] as String? ?? 'فشل تحميل سجل الفواتير.';
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _loadError = 'حدث خطأ غير متوقع أثناء تحميل السجل.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result =
          await _repo.getCustomerInvoiceHistory(widget.customerId, page: _currentPage + 1);
      setState(() {
        _rows.addAll(result.rows);
        _currentPage = result.currentPage;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('سجل فواتير — ${widget.customerName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? AppErrorView(message: _loadError!, onRetry: _load)
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final summary = _summary;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (summary != null) _SummaryCard(summary: summary),
          const SizedBox(height: 12),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('لا توجد فواتير سابقة لهذا العميل.',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ..._rows.map((row) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined, color: AppTheme.primary),
                    title: Text(row.invoiceNumber,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${DateFormat('yyyy-MM-dd HH:mm').format(row.date)} • ${row.delegateName}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          row.netTotal.toStringAsFixed(2),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                        if (row.balanceAddedToDebt > 0)
                          Text('+${row.balanceAddedToDebt.toStringAsFixed(0)} دين',
                              style: const TextStyle(color: AppTheme.danger, fontSize: 10)),
                        if (row.debtReduction > 0)
                          Text('-${row.debtReduction.toStringAsFixed(0)} سداد',
                              style: const TextStyle(color: AppTheme.secondary, fontSize: 10)),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => InvoiceDetailPage(invoiceId: row.id)),
                    ),
                  ),
                )),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(onPressed: _loadMore, child: const Text('تحميل المزيد')),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final CustomerInvoiceHistorySummaryModel summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatColumn(label: 'عدد الفواتير', value: '${summary.totalInvoicesCount}'),
              _StatColumn(
                  label: 'إجمالي المشتريات', value: summary.totalPurchased.toStringAsFixed(2)),
              _StatColumn(
                label: 'الرصيد الحالي',
                value: summary.currentBalance.toStringAsFixed(2),
                color: summary.currentBalance > 0 ? AppTheme.danger : AppTheme.secondary,
              ),
            ],
          ),
        ),
      );
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatColumn({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: color ?? AppTheme.primary)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );
}
