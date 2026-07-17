import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/bluetooth_printer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import 'invoice_page.dart';
import 'invoice_preview_page.dart';
import 'print_invoice_page.dart';

/// Full invoice preview — customer, itemized products/returns, totals.
/// print_invoice_page.dart remains the printer-picker flow, reachable from
/// here as a secondary action rather than the default destination when
/// tapping an invoice in the history list.
class InvoiceDetailPage extends StatefulWidget {
  final int invoiceId;
  /// Whether the delegate's loading is currently accepted/in_transit —
  /// gates the "تعديل" action the same way TransactionsPage gates its
  /// expense/collection edit actions. Defaults to false (view-only).
  final bool hasActiveLoading;
  const InvoiceDetailPage({super.key, required this.invoiceId, this.hasActiveLoading = false});

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  final _api = sl<ApiClient>();
  Map<String, dynamic>? _invoice;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadInvoice();
  }

  Future<void> _loadInvoice() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await _api.dio.get('${ApiEndpoints.delegateInvoices}/${widget.invoiceId}');
      setState(() {
        _invoice = res.data['data'] as Map<String, dynamic>?;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _loading = false;
        _loadError = e.response?.data?['message'] as String? ?? 'فشل تحميل بيانات الفاتورة.';
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _loadError = 'حدث خطأ غير متوقع أثناء تحميل الفاتورة.';
      });
    }
  }

  /// Refreshes unconditionally on return — same rationale as
  /// InvoiceHistoryPage's own post-navigation refresh: simpler and more
  /// robust than threading a specific "did it succeed" result back.
  Future<void> _openEdit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePage(editingInvoiceId: widget.invoiceId),
      ),
    );
    if (mounted) _loadInvoice();
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    return Scaffold(
      appBar: AppBar(
        title: Text(invoice?['invoice_number'] as String? ?? 'تفاصيل الفاتورة'),
        actions: [
          if (invoice != null) ...[
            if (widget.hasActiveLoading)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'تعديل',
                onPressed: _openEdit,
              ),
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'معاينة',
              onPressed: () => _openPreview(context, invoice),
            ),
            IconButton(
              icon: const Icon(Icons.print_rounded),
              tooltip: 'طباعة',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PrintInvoicePage(invoiceId: widget.invoiceId),
                ),
              ),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? AppErrorView(message: _loadError!, onRetry: _loadInvoice)
              : invoice == null
                  ? const Center(child: Text('تعذر عرض الفاتورة'))
                  : _buildBody(context, invoice),
    );
  }

  /// Builds the same InvoicePrintData print_invoice_page.dart's print flow
  /// does (via InvoicePrintData.fromInvoiceJson), so this preview always
  /// shows exactly what would be printed.
  void _openPreview(BuildContext context, Map<String, dynamic> invoice) {
    final configState = context.read<AppConfigBloc>().state;
    final config = configState is AppConfigLoaded ? configState.config : null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePreviewPage(
          data: InvoicePrintData.fromInvoiceJson(
            invoice,
            showPhone: config?.showPhone ?? true,
            companyName: config?.companyName ?? '',
            headerText: config?.headerText,
            footerText: config?.footerText,
            logoUrl: config?.logoUrl,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> invoice) {
    final customer = invoice['customer'] as Map<String, dynamic>? ?? {};
    final items = (invoice['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final returns = (invoice['returns'] as List? ?? []).cast<Map<String, dynamic>>();
    final createdAt = DateTime.tryParse(invoice['created_at'] as String? ?? '');

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(customer['name'] as String? ?? '—',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    if (createdAt != null)
                      Text(DateFormat('yyyy-MM-dd HH:mm').format(createdAt),
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                if ((customer['phone'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(customer['phone'] as String,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (items.isNotEmpty) ...[
          Text('المبيعات', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: items.map((item) => _ItemRow(item: item)).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (returns.isNotEmpty) ...[
          Text('المرتجعات', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: returns.map((item) => _ItemRow(item: item, isReturn: true)).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TotalRow('إجمالي المبيعات', invoice['gross_sales_total']),
                _TotalRow('إجمالي المرتجعات', invoice['total_returns']),
                const Divider(),
                _TotalRow('الصافي', invoice['net_total'], bold: true),
                _TotalRow('النقد المستلم', invoice['cash_received']),
                if (((invoice['balance_added_to_debt'] as num?) ?? 0) > 0)
                  _TotalRow('دين مضاف', invoice['balance_added_to_debt'], color: AppTheme.danger),
                if (((invoice['debt_reduction'] as num?) ?? 0) > 0)
                  _TotalRow('سداد من الدين السابق', invoice['debt_reduction'],
                      color: AppTheme.secondary),
              ],
            ),
          ),
        ),
        if (((invoice['debt_reduction'] as num?) ?? 0) > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppTheme.secondary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم سداد ${((invoice['debt_reduction'] as num)).toStringAsFixed(2)} جنيه من دين العميل السابق.',
                    style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isReturn;
  const _ItemRow({required this.item, this.isReturn = false});

  @override
  Widget build(BuildContext context) {
    final product = item['product'] as Map<String, dynamic>? ?? {};
    final qty = (item['quantity'] as num? ?? 0).toDouble();
    final unitPrice = (item['unit_price'] as num? ?? 0).toDouble();
    final subtotal = (item['subtotal'] as num? ?? 0).toDouble();
    final note = item['price_override_note'] as String?;
    final condition = item['condition'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(product['name'] as String? ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(subtotal.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${qty.toStringAsFixed(2)} ${product['unit'] ?? ''} × ${unitPrice.toStringAsFixed(2)}'
            '${isReturn && condition != null ? ' — $condition' : ''}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(note, style: const TextStyle(fontSize: 11, color: AppTheme.accent)),
          ],
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final dynamic value;
  final bool bold;
  final Color? color;
  const _TotalRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final amount = (value as num? ?? 0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(
            amount.toStringAsFixed(2),
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color ?? (bold ? AppTheme.primary : null),
            ),
          ),
        ],
      ),
    );
  }
}
