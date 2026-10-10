import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/bluetooth_printer.dart';
import '../../../../core/utils/printer_manager.dart';

/// "طابعتي": the remembered printer — its connection state, change / forget
/// it, and the "طباعة تلقائية بعد إصدار الفاتورة" toggle.
class MyPrinterPage extends StatefulWidget {
  const MyPrinterPage({super.key});

  @override
  State<MyPrinterPage> createState() => _MyPrinterPageState();
}

class _MyPrinterPageState extends State<MyPrinterPage> {
  final _manager = sl<PrinterManager>();
  final _printer = sl<BluetoothPrinterService>();
  List<BluetoothInfo>? _devices;
  bool _loadingDevices = false;
  String? _connectingMac;

  @override
  void initState() {
    super.initState();
    _manager.autoConnect();
  }

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    final devices = await _printer.discoverDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loadingDevices = false;
    });
    if (devices.isEmpty) {
      AppSnackbar.showInfo(context, 'لا توجد طابعات مقترنة — اقرن الطابعة من إعدادات البلوتوث أولاً');
    }
  }

  Future<void> _choose(BluetoothInfo device) async {
    setState(() => _connectingMac = device.macAdress);
    final result = await _printer.ensureConnected(device);
    if (!mounted) return;
    setState(() => _connectingMac = null);
    if (result.success) {
      await _manager.savePrinter(device);
      if (!mounted) return;
      setState(() => _devices = null);
      AppSnackbar.showSuccess(context, 'تم حفظ الطابعة: ${device.name}');
    } else {
      AppSnackbar.showError(context, printerConnectErrorMessage(result.error));
    }
  }

  Future<void> _connectNow() async {
    final ok = await _manager.autoConnect();
    if (!mounted) return;
    if (!ok) {
      final bluetoothOn = await _printer.isBluetoothEnabled;
      final permitted = await _printer.hasBluetoothPermission();
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        printerConnectErrorMessage(!permitted
            ? PrinterConnectError.permissionDenied
            : !bluetoothOn
                ? PrinterConnectError.bluetoothOff
                : PrinterConnectError.unknown),
      );
    }
  }

  Future<void> _forget() async {
    await _manager.forget();
    if (mounted) AppSnackbar.showInfo(context, 'تم نسيان الطابعة');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طابعتي')),
      body: ListenableBuilder(
        listenable: _manager,
        builder: (context, _) {
          final saved = _manager.savedPrinter;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    switch (_manager.linkState) {
                      PrinterLinkState.connected => Icons.bluetooth_connected,
                      PrinterLinkState.connecting => Icons.bluetooth_searching,
                      _ => Icons.bluetooth_disabled,
                    },
                    color: _manager.linkState == PrinterLinkState.connected ? AppTheme.secondary : null,
                  ),
                  title: Text(saved?.name ?? 'لم يتم اختيار طابعة'),
                  subtitle: Text(saved == null
                      ? 'اختر طابعة مرة واحدة وسيتذكرها التطبيق'
                      : switch (_manager.linkState) {
                          PrinterLinkState.connected => 'متصلة',
                          PrinterLinkState.connecting => 'جارٍ الاتصال…',
                          _ => 'غير متصلة — سيعيد التطبيق المحاولة تلقائياً',
                        }),
                  trailing: saved != null && _manager.linkState != PrinterLinkState.connected
                      ? TextButton(onPressed: _connectNow, child: const Text('اتصال الآن'))
                      : null,
                ),
              ),
              if (saved != null)
                SwitchListTile(
                  title: const Text('طباعة تلقائية بعد إصدار الفاتورة'),
                  value: _manager.autoPrint,
                  onChanged: _manager.setAutoPrint,
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loadingDevices ? null : _loadDevices,
                icon: _loadingDevices
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined),
                label: Text(saved == null ? 'اختيار طابعة' : 'تغيير الطابعة'),
              ),
              if (saved != null)
                TextButton.icon(
                  onPressed: _forget,
                  icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                  label: const Text('نسيان الطابعة', style: TextStyle(color: AppTheme.danger)),
                ),
              if (_devices != null)
                for (final d in _devices!)
                  Card(
                    child: ListTile(
                      title: Text(d.name),
                      subtitle: Text(d.macAdress, textDirection: TextDirection.ltr),
                      trailing: _connectingMac == d.macAdress
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : (saved?.macAdress == d.macAdress ? const Icon(Icons.check, color: AppTheme.secondary) : null),
                      onTap: _connectingMac == null ? () => _choose(d) : null,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
