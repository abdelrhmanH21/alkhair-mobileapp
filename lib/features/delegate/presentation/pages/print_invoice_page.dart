import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/bluetooth_printer.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';

class PrintInvoicePage extends StatefulWidget {
  final int invoiceId;
  const PrintInvoicePage({super.key, required this.invoiceId});

  @override
  State<PrintInvoicePage> createState() => _PrintInvoicePageState();
}

class _PrintInvoicePageState extends State<PrintInvoicePage> {
  final _printer = sl<BluetoothPrinterService>();
  final _api     = sl<ApiClient>();
  Map<String, dynamic>? _invoiceData;
  bool _loading = true;
  List<BluetoothInfo> _devices = [];
  BluetoothInfo? _selectedDevice;
  bool _printing = false;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _loadInvoice();
    _discoverDevices();
  }

  Future<void> _loadInvoice() async {
    try {
      final res = await _api.dio
          .get('${ApiEndpoints.delegateInvoices}/${widget.invoiceId}');
      setState(() {
        _invoiceData = res.data['data'] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _discoverDevices() async {
    final devices = await _printer.discoverDevices();
    setState(() => _devices = devices);
  }

  Future<void> _connect() async {
    if (_selectedDevice == null) return;
    final ok = await _printer.connect(_selectedDevice!.macAdress);
    setState(() => _connected = ok);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'متصل بالطابعة' : 'فشل الاتصال بالطابعة'),
      backgroundColor: ok ? AppTheme.secondary : AppTheme.danger,
    ));
  }

  Future<void> _print() async {
    if (_invoiceData == null) return;
    setState(() => _printing = true);

    final authState = context.read<AuthBloc>().state;
    final delegateName =
        authState is AuthAuthenticated ? authState.user.name : 'مندوب';

    final customer =
        _invoiceData!['customer'] as Map<String, dynamic>? ?? {};
    final items     = _invoiceData!['items'] as List? ?? [];
    final returns   = _invoiceData!['returns'] as List? ?? [];

    final data = InvoicePrintData(
      invoiceNumber: _invoiceData!['invoice_number'] as String? ?? '',
      clientName: customer['name'] as String? ?? '',
      clientPhone: customer['phone'] as String? ?? '',
      delegateName: delegateName,
      issuedAt: DateTime.tryParse(
              _invoiceData!['created_at'] as String? ?? '') ??
          DateTime.now(),
      salesItems: items.map((e) {
        final m = e as Map<String, dynamic>;
        final p = m['product'] as Map<String, dynamic>? ?? {};
        return PrintLineItem(
          productName: p['name'] as String? ?? '',
          quantity: (m['quantity'] as num).toDouble(),
          unitPrice: (m['unit_price'] as num).toDouble(),
          subtotal: (m['subtotal'] as num).toDouble(),
        );
      }).toList(),
      returnedItems: returns.map((e) {
        final m = e as Map<String, dynamic>;
        final p = m['product'] as Map<String, dynamic>? ?? {};
        return PrintLineItem(
          productName: p['name'] as String? ?? '',
          quantity: (m['quantity'] as num).toDouble(),
          unitPrice: (m['unit_price'] as num).toDouble(),
          subtotal: (m['subtotal'] as num).toDouble(),
        );
      }).toList(),
      grossSales:
          (_invoiceData!['gross_sales_total'] as num? ?? 0).toDouble(),
      totalReturns: (_invoiceData!['total_returns'] as num? ?? 0).toDouble(),
      netTotal: (_invoiceData!['net_total'] as num? ?? 0).toDouble(),
      cashReceived: (_invoiceData!['cash_received'] as num? ?? 0).toDouble(),
      balanceAddedToDebt:
          (_invoiceData!['balance_added_to_debt'] as num? ?? 0).toDouble(),
    );

    final ok = await _printer.printInvoice(data);
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'تم الطباعة بنجاح' : 'فشل الطباعة'),
      backgroundColor: ok ? AppTheme.secondary : AppTheme.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طباعة الفاتورة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_invoiceData != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'فاتورة: ${_invoiceData!['invoice_number']}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'العميل: ${(_invoiceData!['customer'] as Map?)?['name'] ?? ''}',
                            ),
                            Text(
                              'الصافي: ${_invoiceData!['net_total']}',
                              style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const Text('الطابعة البلوتوث',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<BluetoothInfo>(
                          initialValue: _selectedDevice,
                          hint: const Text('اختر طابعة'),
                          items: _devices
                              .map((d) => DropdownMenuItem(
                                    value: d,
                                    child: Text(d.name,
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (d) =>
                              setState(() => _selectedDevice = d),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _discoverDevices,
                        tooltip: 'بحث عن الطابعات',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _selectedDevice == null ? null : _connect,
                    icon: Icon(
                      _connected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth,
                      color: _connected ? AppTheme.secondary : null,
                    ),
                    label: Text(_connected ? 'متصل' : 'اتصال بالطابعة'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: (!_connected || _printing) ? null : _print,
                    icon: _printing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.print_rounded),
                    label: Text(
                        _printing ? 'جارٍ الطباعة...' : 'طباعة الفاتورة'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                  ),
                ],
              ),
            ),
    );
  }
}
