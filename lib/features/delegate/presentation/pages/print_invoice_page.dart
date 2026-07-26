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
import 'invoice_preview_page.dart';

class PrintInvoicePage extends StatefulWidget {
  /// Delegate-invoice path: fetched by id from
  /// `GET /delegate/invoices/{id}` and mapped via
  /// `InvoicePrintData.fromInvoiceJson`.
  final int? invoiceId;

  /// Pre-built print-data path: for callers (e.g. the admin "عملية بيع"
  /// screen) that already have everything a receipt needs right in their
  /// own submit response, with a shape too different from the delegate
  /// invoice JSON to share `fromInvoiceJson` — they build an
  /// [InvoicePrintData] themselves (see admin_sale_page.dart's small
  /// adapter) and this screen just renders/prints it, skipping the fetch
  /// entirely. Reuses this exact screen (and InvoicePreviewPage/
  /// ReceiptPreviewCard below it) rather than a parallel print screen, so
  /// both entry points always share one rendering/printing pipeline.
  final InvoicePrintData? initialData;

  const PrintInvoicePage({super.key, this.invoiceId, this.initialData})
      : assert(invoiceId != null || initialData != null,
            'PrintInvoicePage needs either invoiceId or initialData');

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
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _loading = false;
    } else {
      _loadInvoice();
    }
    _discoverDevices();
    _restoreConnection();
  }

  /// Re-shows whatever printer this DI-singleton service is already
  /// connected to (or was last connected to) from a previous visit to this
  /// screen, without forcing the user to re-pick a device and tap "اتصال"
  /// again every single time. [BluetoothPrinterService.ensureConnected]
  /// itself verifies the connection is still actually live before deciding
  /// whether a real reconnect handshake is needed.
  Future<void> _restoreConnection() async {
    final remembered = _printer.connectedDevice;
    if (remembered == null) return;
    setState(() {
      _selectedDevice = remembered;
      _connecting = true;
    });
    final result = await _printer.ensureConnected(remembered);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _connected = result.success;
    });
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
    setState(() => _connecting = true);
    final result = await _printer.ensureConnected(_selectedDevice!);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _connected = result.success;
    });
    if (result.success) {
      AppSnackbar.showSuccess(context, 'متصل بالطابعة');
      return;
    }
    AppSnackbar.showError(context, _connectErrorMessage(result.error));
  }

  String _connectErrorMessage(PrinterConnectError? error) {
    switch (error) {
      case PrinterConnectError.permissionDenied:
        return 'تأكد من صلاحيات البلوتوث في إعدادات الهاتف';
      case PrinterConnectError.bluetoothOff:
        return 'يرجى تفعيل البلوتوث في الهاتف';
      case PrinterConnectError.timeout:
        return 'انتهت مهلة الاتصال، تأكد أن الطابعة قريبة ومُشغّلة وحاول مرة أخرى';
      case PrinterConnectError.unknown:
      case null:
        return 'فشل الاتصال بالطابعة، تأكد من تشغيلها وقربها من الهاتف';
    }
  }

  /// Same construction print and preview both use, so they always render
  /// from identical data. When [PrintInvoicePage.initialData] was supplied,
  /// the caller already built the final print data (including config
  /// fields) themselves, so this just returns it unchanged. Otherwise
  /// awaits [AppConfigBloc.ensureLoaded] rather than reading its state
  /// directly, so a config fetch that failed/hadn't finished at app startup
  /// doesn't silently print a logo-less, company-name-less receipt for the
  /// rest of the session (see ensureLoaded's doc comment).
  Future<InvoicePrintData> _buildPrintData() async {
    final initial = widget.initialData;
    if (initial != null) return initial;
    final config = await context.read<AppConfigBloc>().ensureLoaded();
    return InvoicePrintData.fromInvoiceJson(
      _invoiceData!,
      showPhone: config?.showPhone ?? true,
      companyName: config?.companyName ?? '',
      headerText: config?.headerText,
      footerText: config?.footerText,
      logoUrl: config?.logoUrl,
      paperWidth: config?.paperWidth ?? '80mm',
    );
  }

  Future<void> _openPreview() async {
    final data = await _buildPrintData();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoicePreviewPage(data: data)),
    );
  }

  Future<void> _print() async {
    setState(() => _printing = true);

    final data = await _buildPrintData();
    if (!mounted) return;
    // Passing the selected device lets printInvoice fall back to a full
    // reconnect+retry if the "persistent" connection turned out to be
    // stale (printer powered off/out of range) instead of just failing.
    final ok = await _printer.printInvoice(data, device: _selectedDevice);
    if (!mounted) return;
    // Reflect whatever printInvoice's own reconnect attempt actually left
    // the connection in, so a failure that couldn't be recovered disables
    // the print button again instead of showing a stale "متصل" state.
    final stillConnected = await _printer.isConnected;
    if (!mounted) return;
    setState(() {
      _printing = false;
      _connected = stillConnected;
    });
    if (ok) {
      AppSnackbar.showSuccess(context, 'تم الطباعة بنجاح');
    } else {
      AppSnackbar.showError(context, 'فشل الطباعة، تأكد من تشغيل الطابعة وقربها من الهاتف');
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
                  if (_invoiceData != null || widget.initialData != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'فاتورة: ${widget.initialData?.invoiceNumber ?? _invoiceData!['invoice_number']}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'العميل: ${widget.initialData?.clientName ?? (_invoiceData!['customer'] as Map?)?['name'] ?? ''}',
                            ),
                            Text(
                              'الصافي: ${widget.initialData?.netTotal ?? _invoiceData!['net_total']}',
                              style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openPreview,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('معاينة الفاتورة'),
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
                    onPressed:
                        (_selectedDevice == null || _connecting) ? null : _connect,
                    icon: _connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _connected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth,
                            color: _connected ? AppTheme.secondary : null,
                          ),
                    label: Text(_connecting
                        ? 'جارٍ الاتصال...'
                        : (_connected ? 'متصل' : 'اتصال بالطابعة')),
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
