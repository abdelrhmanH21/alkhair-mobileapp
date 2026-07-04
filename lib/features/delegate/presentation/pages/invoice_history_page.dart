import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/invoice_model.dart';
import 'invoice_detail_page.dart';

class InvoiceHistoryPage extends StatefulWidget {
  /// Bumped by DelegateHomePage each time this tab is (re)selected — when
  /// pushed as its own route (from the invoice screen's app bar, or from the
  /// completed-loading view) this stays at its default and has no effect,
  /// since a fresh push already re-runs initState() on its own.
  final int refreshTick;
  const InvoiceHistoryPage({super.key, this.refreshTick = 0});

  @override
  State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> {
  List<DelegateInvoiceModel> _invoices = [];

  @override
  void initState() {
    super.initState();
    context.read<DelegateBloc>().add(DelegateInvoicesFetched());
  }

  @override
  void didUpdateWidget(covariant InvoiceHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      context.read<DelegateBloc>().add(DelegateInvoicesFetched());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الفواتير')),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateInvoicesLoaded) {
            setState(() => _invoices = state.invoices);
          } else if (state is DelegateFailure) {
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
                  trailing: Column(
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
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvoiceDetailPage(invoiceId: inv.id),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
