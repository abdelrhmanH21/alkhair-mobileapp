import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_printer.dart';

/// Connection state of the saved printer, as far as the app knows.
enum PrinterLinkState { none, connecting, connected, disconnected }

enum PrintJobStatus { printing, success, failed }

/// The latest one-tap print, for the inline status (جاري الطباعة… / تمت
/// الطباعة / إعادة الطباعة + اختيار طابعة).
class PrintJob {
  final int invoiceId;
  final PrintJobStatus status;
  final String? message;
  /// True when the failure was "not even connected" (or no printer):
  /// the "اختيار طابعة" action is the useful one then.
  final bool connectFailed;
  const PrintJob(this.invoiceId, this.status, {this.message, this.connectFailed = false});
}

/// User-facing text for a connect failure (shared by the print screen and
/// the one-tap flow — Bluetooth off / permission denied stay explicit).
String printerConnectErrorMessage(PrinterConnectError? error) {
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

String printOutcomeMessage(PrintOutcome outcome) {
  switch (outcome) {
    case PrintOutcome.success:
      return 'تمت الطباعة';
    case PrintOutcome.renderFailed:
      return 'تعذر تجهيز الفاتورة للطباعة، حاول مرة أخرى';
    case PrintOutcome.sendFailed:
      return 'فشل الطباعة، تأكد من تشغيل الطابعة وقربها من الهاتف';
    case PrintOutcome.interrupted:
      return 'انقطع الاتصال أثناء الطباعة وقد تكون الفاتورة طُبعت جزئياً';
  }
}

/// "طابعتي": remembers the printer after the first successful connection,
/// keeps it connected in the background, and prints in one tap.
///
/// Sits on top of [BluetoothPrinterService] (its persistent-connection
/// logic, timeouts and off-UI-thread raster encoding are reused as-is).
///  - [savePrinter] after a successful connect; [forget]; [autoPrint]
///    toggle (ON by default once a printer is saved).
///  - [autoConnect]: silent, non-blocking, never prompts for permission and
///    never shows an error; retries with backoff (5 s → 60 s) when the
///    printer can't be reached, and re-checks the link when the app
///    returns to the foreground.
///  - [printInvoice]: one job at a time (a second tap while printing is
///    ignored — no accidental double print); the invoice itself is already
///    saved before this is ever called, so a failed print never loses or
///    duplicates it — [retryLast] only reprints.
class PrinterManager extends ChangeNotifier with WidgetsBindingObserver {
  static const _kMac = 'saved_printer_mac';
  static const _kName = 'saved_printer_name';
  static const _kAutoPrint = 'saved_printer_auto_print';

  final BluetoothPrinterService _printer;
  final SharedPreferences _prefs;
  final List<Duration> _backoff;

  PrinterManager(
    this._printer,
    this._prefs, {
    List<Duration> backoff = const [
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 40),
      Duration(seconds: 60),
    ],
  }) : _backoff = backoff;

  // ── Saved printer ────────────────────────────────────────────────────────
  BluetoothInfo? get savedPrinter {
    final mac = _prefs.getString(_kMac);
    if (mac == null || mac.isEmpty) return null;
    return BluetoothInfo(name: _prefs.getString(_kName) ?? mac, macAdress: mac);
  }

  bool get hasSavedPrinter => savedPrinter != null;

  /// Defaults to ON once a printer is saved.
  bool get autoPrint => _prefs.getBool(_kAutoPrint) ?? true;

  Future<void> setAutoPrint(bool value) async {
    await _prefs.setBool(_kAutoPrint, value);
    notifyListeners();
  }

  Future<void> savePrinter(BluetoothInfo device) async {
    final changed = _prefs.getString(_kMac) != device.macAdress;
    await _prefs.setString(_kMac, device.macAdress);
    await _prefs.setString(_kName, device.name);
    if (changed) _attempt = 0;
    _link = PrinterLinkState.connected;
    notifyListeners();
  }

  Future<void> forget() async {
    _retryTimer?.cancel();
    await _prefs.remove(_kMac);
    await _prefs.remove(_kName);
    await _prefs.remove(_kAutoPrint);
    await _printer.disconnect();
    _link = PrinterLinkState.none;
    _lastJob = null;
    notifyListeners();
  }

  // ── Connection ───────────────────────────────────────────────────────────
  PrinterLinkState _link = PrinterLinkState.none;
  PrinterLinkState get linkState => hasSavedPrinter ? _link : PrinterLinkState.none;

  Timer? _retryTimer;
  int _attempt = 0;
  Future<bool>? _connecting;
  bool _observing = false;

  /// Call when delegate screens appear. Idempotent and non-blocking.
  void startAutoConnect() {
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    unawaited(autoConnect());
  }

  void stopAutoConnect() {
    if (_observing) {
      _observing = false;
      WidgetsBinding.instance.removeObserver(this);
    }
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The link may have dropped while we were away — verify and reconnect.
      _attempt = 0;
      unawaited(autoConnect());
    } else if (state == AppLifecycleState.paused) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  /// Silent background connect to the saved printer. Never prompts for a
  /// permission, never throws, never shows UI; on failure schedules a retry
  /// with backoff. Returns whether the printer is connected.
  Future<bool> autoConnect() {
    return _connecting ??= _autoConnect().whenComplete(() => _connecting = null);
  }

  Future<bool> _autoConnect() async {
    final device = savedPrinter;
    if (device == null) return false;
    try {
      if (!await _printer.hasBluetoothPermission() || !await _printer.isBluetoothEnabled) {
        _setLink(PrinterLinkState.disconnected);
        _scheduleRetry();
        return false;
      }
      if (_printer.connectedDevice?.macAdress == device.macAdress && await _printer.isConnected) {
        _attempt = 0;
        _setLink(PrinterLinkState.connected);
        return true;
      }
      _setLink(PrinterLinkState.connecting);
      final result = await _printer.ensureConnected(device);
      if (result.success) {
        _attempt = 0;
        _setLink(PrinterLinkState.connected);
        return true;
      }
    } catch (e) {
      debugPrint('[printer] auto-connect failed: $e');
    }
    _setLink(PrinterLinkState.disconnected);
    _scheduleRetry();
    return false;
  }

  void _scheduleRetry() {
    if (!_observing) return;
    _retryTimer?.cancel();
    final delay = _backoff[_attempt.clamp(0, _backoff.length - 1)];
    _attempt++;
    _retryTimer = Timer(delay, () => unawaited(autoConnect()));
  }

  void _setLink(PrinterLinkState state) {
    if (_link == state) return;
    _link = state;
    notifyListeners();
  }

  // ── One-tap print ────────────────────────────────────────────────────────
  PrintJob? _lastJob;
  PrintJob? get lastJob => _lastJob;
  bool get isPrinting => _lastJob?.status == PrintJobStatus.printing;

  Future<InvoicePrintData> Function()? _lastLoader;

  void clearLastJob() {
    if (_lastJob == null || isPrinting) return;
    _lastJob = null;
    notifyListeners();
  }

  /// Prints invoice [invoiceId] on the saved printer. [load] builds its
  /// print data (fetching the invoice is part of the job, so a slow
  /// network shows as "جاري الطباعة…" too). Returns false without doing
  /// anything if a print is already running.
  Future<bool> printInvoice(int invoiceId, Future<InvoicePrintData> Function() load) async {
    if (isPrinting) return false;
    final device = savedPrinter;
    _lastLoader = load;
    if (device == null) {
      _finish(invoiceId, PrintJobStatus.failed, 'لم يتم اختيار طابعة بعد', connectFailed: true);
      return false;
    }
    _lastJob = PrintJob(invoiceId, PrintJobStatus.printing);
    notifyListeners();

    try {
      _setLink(PrinterLinkState.connecting);
      final connect = await _printer.ensureConnected(device);
      if (!connect.success) {
        _setLink(PrinterLinkState.disconnected);
        _finish(invoiceId, PrintJobStatus.failed, printerConnectErrorMessage(connect.error), connectFailed: true);
        _scheduleRetry();
        return false;
      }
      _setLink(PrinterLinkState.connected);

      final InvoicePrintData data;
      try {
        data = await load();
      } catch (e) {
        debugPrint('[printer] building print data failed: $e');
        _finish(invoiceId, PrintJobStatus.failed, printOutcomeMessage(PrintOutcome.renderFailed));
        return false;
      }

      final outcome = await _printer.printInvoice(data, device: device);
      _setLink(await _printer.isConnected ? PrinterLinkState.connected : PrinterLinkState.disconnected);
      if (outcome == PrintOutcome.success) {
        _finish(invoiceId, PrintJobStatus.success, printOutcomeMessage(outcome));
        return true;
      }
      _finish(invoiceId, PrintJobStatus.failed, printOutcomeMessage(outcome));
      return false;
    } catch (e) {
      // printInvoice itself never throws; this is a last-resort guard so
      // the job can never stay stuck on "printing".
      debugPrint('[printer] print job failed: $e');
      _finish(invoiceId, PrintJobStatus.failed, printOutcomeMessage(PrintOutcome.sendFailed));
      return false;
    }
  }

  /// Reprints the last job (the invoice is already saved — never resubmits).
  Future<bool> retryLast() async {
    final job = _lastJob;
    final load = _lastLoader;
    if (job == null || load == null) return false;
    return printInvoice(job.invoiceId, load);
  }

  void _finish(int invoiceId, PrintJobStatus status, String? message, {bool connectFailed = false}) {
    _lastJob = PrintJob(invoiceId, status, message: message, connectFailed: connectFailed);
    notifyListeners();
  }

  @override
  void dispose() {
    stopAutoConnect();
    super.dispose();
  }
}
