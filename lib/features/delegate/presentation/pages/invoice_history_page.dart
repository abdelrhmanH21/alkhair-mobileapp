import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../../data/models/invoice_model.dart';
import 'invoice_detail_page.dart';
import 'invoice_page.dart';

class InvoiceHistoryPage extends StatefulWidget {
  /// Bumped by DelegateHomePage each time this tab is (re)selected — when
  /// pushed as its own route (from the invoice screen's app bar, or from the
  /// completed-loading view) this stays at its default and has no effect,
  /// since a fresh push already re-runs initState() on its own.
  final int refreshTick;
  /// Whether the delegate's loading is currently accepted/in_transit —
  /// gates the "تعديل" entry point the same way TransactionsPage gates its
  /// expense/collection edit actions. Defaults to false (view-only) so
  /// callers that don't know the current loading state (or intentionally
  /// don't have one, like loading_page.dart's "completed" view) never show
  /// an edit affordance the backend would reject anyway.
  final bool hasActiveLoading;
  const InvoiceHistoryPage({super.key, this.refreshTick = 0, this.hasActiveLoading = false});

  @override
  State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> {
  List<DelegateInvoiceModel> _invoices = [];

  // This tab lives forever inside DelegateHomePage's IndexedStack, sharing
  // one DelegateBloc with every other tab — tracks this page's own
  // outstanding fetch by requestId so an unrelated DelegateFailure elsewhere
  // (e.g. a sibling tab's poll) can never surface here as a stray SnackBar.
  final _tracker = RequestTracker<bool>();

  void _fetch() {
    final event = DelegateInvoicesFetched();
    _tracker.start(event.requestId, true);
    context.read<DelegateBloc>().add(event);
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant InvoiceHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      _fetch();
    }
  }

  /// Re-fetches the list after returning from viewing/editing an invoice —
  /// unconditional rather than gated on a specific pop result, so an edit
  /// made further down the navigation stack (e.g. from InvoiceDetailPage's
  /// own تعديل button) still refreshes this list's totals.
  Future<void> _openDetail(int invoiceId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            InvoiceDetailPage(invoiceId: invoiceId, hasActiveLoading: widget.hasActiveLoading),
      ),
    );
    if (mounted) _fetch();
  }

  Future<void> _openEdit(int invoiceId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<DelegateBloc>(),
          child: InvoicePage(editingInvoiceId: invoiceId),
        ),
      ),
    );
    if (mounted) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الفواتير')),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateInvoicesLoaded) {
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() => _invoices = state.invoices);
          } else if (state is DelegateFailure) {
            if (_tracker.resolve(state.requestId) == null) return;
            AppSnackbar.showError(ctx, state.message);
          }
        },
        builder: (_, state) {
          if (state is DelegateLoading && _invoices.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_invoices.isEmpty) {
            return const Center(
                child: Text('لا توجد فواتير بعد.',
                    style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            itemCount: _invoices.length,
            itemBuilder: (_, i) {
              final inv = _invoices[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined,
                      color: AppTheme.primary),
                  title: Text(inv.customerName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${inv.invoiceNumber} • ${DateFormat('HH:mm').format(inv.createdAt)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.hasActiveLoading)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'تعديل',
                          onPressed: () => _openEdit(inv.id),
                        ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            inv.netTotal.toStringAsFixed(2),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary),
                          ),
                          if (inv.balanceAddedToDebt > 0)
                            Text(
                              '+${inv.balanceAddedToDebt.toStringAsFixed(0)} دين',
                              style: const TextStyle(
                                  color: AppTheme.danger, fontSize: 10),
                            ),
                        ],
                      ),
                    ],
                  ),
                  onTap: () => _openDetail(inv.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
