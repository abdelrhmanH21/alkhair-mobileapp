import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/bluetooth_printer.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';

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
  String? _loadError;
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

  Future<void> _discoverDevices() async {
    final devices = await _printer.discoverDevices();
    setState(() => _devices = devices);
  }

  Future<void> _connect() async {
    if (_selectedDevice == null) return;
    final ok = await _printer.connect(_selectedDevice!.macAdress);
    setState(() => _connected = ok);
    if (!mounted) return;
    if (ok) {
      AppSnackbar.showSuccess(context, 'متصل بالطابعة');
    } else {
      AppSnackbar.showError(context, 'فشل الاتصال بالطابعة');
    }
  }

  Future<void> _print() async {
    if (_invoiceData == null) return;
    setState(() => _printing = true);

    final configState = context.read<AppConfigBloc>().state;
    final config = configState is AppConfigLoaded ? configState.config : null;

    final customer =
        _invoiceData!['customer'] as Map<String, dynamic>? ?? {};
    final delegate  = _invoiceData!['delegate'] as Map<String, dynamic>? ?? {};
    final items     = _invoiceData!['items'] as List? ?? [];
    final returns   = _invoiceData!['returns'] as List? ?? [];

    final data = InvoicePrintData(
      invoiceNumber: _invoiceData!['invoice_number'] as String? ?? '',
      clientName: customer['name'] as String? ?? '',
      clientPhone: customer['phone'] as String? ?? '',
      showPhone: config?.showPhone ?? true,
      delegateName: delegate['name'] as String? ?? 'مندوب',
      issuedAt: DateTime.tryParse(
              _invoiceData!['created_at'] as String? ?? '') ??
          DateTime.now(),
      salesItems: items.map((e) {
        final m = e as Map<String, dynamic>;
        final p = m['product'] as Map<String, dynamic>? ?? {};
        return PrintLineItem(
          productName: p['name'] as String? ?? '',
          unit: p['unit'] as String? ?? '',
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
          unit: p['unit'] as String? ?? '',
          quantity: (m['quantity'] as num).toDouble(),
          unitPrice: (m['unit_price'] as num).toDouble(),
          subtotal: (m['subtotal'] as num).toDouble(),
        );
      }).toList(),
      grossSales:
          (_invoiceData!['gross_sales_total'] as num? ?? 0).toDouble(),
      discountAmount:
          (_invoiceData!['discount_amount'] as num? ?? 0).toDouble(),
      totalReturns: (_invoiceData!['total_returns'] as num? ?? 0).toDouble(),
      netTotal: (_invoiceData!['net_total'] as num? ?? 0).toDouble(),
      cashReceived: (_invoiceData!['cash_received'] as num? ?? 0).toDouble(),
      balanceAddedToDebt:
          (_invoiceData!['balance_added_to_debt'] as num? ?? 0).toDouble(),
      customerBalanceAfter: (customer['balance'] as num? ?? 0).toDouble(),
      companyName: config?.companyName ?? '',
      headerText: config?.headerText,
      footerText: config?.footerText,
      logoUrl: config?.logoUrl,
    );

    final ok = await _printer.printInvoice(data);
    if (!mounted) return;
    setState(() => _printing = false);
    if (ok) {
      AppSnackbar.showSuccess(context, 'تم الطباعة بنجاح');
    } else {
      AppSnackbar.showError(context, 'فشل الطباعة');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طباعة الفاتورة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
                    const SizedBox(height: 12),
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {
                        _loading = true;
                        _loadError = null;
                        _loadInvoice();
                      }),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            )
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
