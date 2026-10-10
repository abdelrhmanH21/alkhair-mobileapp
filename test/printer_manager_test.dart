import 'dart:async';

import 'package:alkhair_mobileapp/core/di/service_locator.dart';
import 'package:alkhair_mobileapp/core/utils/bluetooth_printer.dart';
import 'package:alkhair_mobileapp/core/utils/printer_manager.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/printing/quick_print.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Part 2 — one-tap printing: the printer is remembered, connects silently,
/// prints once per tap, and a failed print never touches the (already
/// saved) invoice — retry only reprints.
class _FakePrinter implements BluetoothPrinterService {
  bool permission = true;
  bool bluetoothOn = true;
  PrinterConnectResult connectResult = const PrinterConnectResult.ok();
  PrintOutcome outcome = PrintOutcome.success;
  Completer<void>? holdPrint;
  int connectCalls = 0;
  int printCalls = 0;
  bool linkUp = false;
  BluetoothInfo? device;

  @override
  Future<bool> hasBluetoothPermission() async => permission;
  @override
  Future<bool> get isBluetoothEnabled async => bluetoothOn;
  @override
  Future<bool> get isConnected async => linkUp;
  @override
  BluetoothInfo? get connectedDevice => device;

  @override
  Future<PrinterConnectResult> ensureConnected(BluetoothInfo d) async {
    connectCalls++;
    if (connectResult.success) {
      linkUp = true;
      device = d;
    }
    return connectResult;
  }

  @override
  Future<PrintOutcome> printInvoice(InvoicePrintData data,
      {BluetoothInfo? device, void Function(PrintStage stage, double progress)? onProgress}) async {
    printCalls++;
    if (holdPrint != null) await holdPrint!.future;
    return outcome;
  }

  @override
  Future<void> disconnect() async {
    linkUp = false;
    device = null;
  }

  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

InvoicePrintData _data() => InvoicePrintData.fromInvoiceJson({
      'id': 1,
      'invoice_number': 'INV-1',
      'customer_id': 5,
      'customer': {'name': 'عميل', 'phone': ''},
      'items': [],
      'returns': [],
      'created_at': '2026-10-10T10:00:00Z',
    }, showPhone: true, companyName: 'الخير', paperWidth: '80mm');

final _xp = BluetoothInfo(name: 'XP-323B', macAdress: '66:22:AA:BB:CC:DD');

Future<(PrinterManager, _FakePrinter)> _manager({bool saved = true}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final printer = _FakePrinter();
  final m = PrinterManager(printer, prefs, backoff: const [Duration(seconds: 5), Duration(seconds: 10)]);
  if (saved) await m.savePrinter(_xp);
  return (m, printer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('saved printer', () {
    test('is persisted (survives a new manager) with auto-print ON by default; forget clears it', () async {
      final (m, printer) = await _manager();
      expect(m.hasSavedPrinter, isTrue);
      expect(m.autoPrint, isTrue);

      final again = PrinterManager(printer, await SharedPreferences.getInstance());
      expect(again.savedPrinter!.macAdress, _xp.macAdress);
      expect(again.savedPrinter!.name, 'XP-323B');

      await m.setAutoPrint(false);
      expect(again.autoPrint, isFalse);

      await m.forget();
      expect(again.hasSavedPrinter, isFalse);
      expect(m.linkState, PrinterLinkState.none);
    });
  });

  group('auto-connect', () {
    test('silently connects to the saved printer', () async {
      final (m, printer) = await _manager();
      expect(await m.autoConnect(), isTrue);
      expect(printer.connectCalls, 1);
      expect(m.linkState, PrinterLinkState.connected);
      // Already connected → no second handshake.
      expect(await m.autoConnect(), isTrue);
      expect(printer.connectCalls, 1);
    });

    test('never prompts: without permission or with Bluetooth off it does not even try to connect', () async {
      final (m, printer) = await _manager();
      printer.permission = false;
      expect(await m.autoConnect(), isFalse);
      printer
        ..permission = true
        ..bluetoothOn = false;
      expect(await m.autoConnect(), isFalse);
      expect(printer.connectCalls, 0);
      expect(m.lastJob, isNull, reason: 'no error surfaced for a background attempt');
    });

    testWidgets('a dropped / unreachable printer is retried with backoff', (tester) async {
      final (m, printer) = await _manager();
      printer.connectResult = const PrinterConnectResult.fail(PrinterConnectError.timeout);
      m.startAutoConnect();
      await tester.pump();
      expect(printer.connectCalls, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(printer.connectCalls, 2);
      await tester.pump(const Duration(seconds: 9));
      expect(printer.connectCalls, 2, reason: 'second wait is 10s');
      printer.connectResult = const PrinterConnectResult.ok();
      await tester.pump(const Duration(seconds: 1));
      expect(printer.connectCalls, 3);
      expect(m.linkState, PrinterLinkState.connected);
      m.stopAutoConnect();
    });
  });

  group('one-tap print', () {
    test('prints with the saved printer', () async {
      final (m, printer) = await _manager();
      var loads = 0;
      final ok = await m.printInvoice(7, () async {
        loads++;
        return _data();
      });
      expect(ok, isTrue);
      expect(printer.printCalls, 1);
      expect(loads, 1);
      expect(m.lastJob!.status, PrintJobStatus.success);
    });

    test('a second tap while printing is ignored — no double print', () async {
      final (m, printer) = await _manager();
      printer.holdPrint = Completer<void>();
      final first = m.printInvoice(7, () async => _data());
      await Future<void>.delayed(Duration.zero);
      expect(m.isPrinting, isTrue);
      expect(await m.printInvoice(7, () async => _data()), isFalse);
      printer.holdPrint!.complete();
      expect(await first, isTrue);
      expect(printer.printCalls, 1);
    });

    test('a failed print keeps the invoice; retry only reprints', () async {
      final (m, printer) = await _manager();
      printer.outcome = PrintOutcome.sendFailed;
      var loads = 0;
      Future<InvoicePrintData> load() async {
        loads++;
        return _data();
      }

      expect(await m.printInvoice(7, load), isFalse);
      expect(m.lastJob!.status, PrintJobStatus.failed);
      expect(m.lastJob!.message, contains('فشل الطباعة'));

      printer.outcome = PrintOutcome.success;
      expect(await m.retryLast(), isTrue);
      expect(m.lastJob!.invoiceId, 7);
      expect(printer.printCalls, 2);
      expect(loads, 2, reason: 'reprint re-reads the saved invoice; nothing is resubmitted');
    });

    test('Bluetooth off / permission denied stay explicit messages', () async {
      final (m, printer) = await _manager();
      printer.connectResult = const PrinterConnectResult.fail(PrinterConnectError.bluetoothOff);
      await m.printInvoice(7, () async => _data());
      expect(m.lastJob!.message, 'يرجى تفعيل البلوتوث في الهاتف');
      expect(m.lastJob!.connectFailed, isTrue);
      expect(printer.printCalls, 0);

      printer.connectResult = const PrinterConnectResult.fail(PrinterConnectError.permissionDenied);
      await m.printInvoice(7, () async => _data());
      expect(m.lastJob!.message, 'تأكد من صلاحيات البلوتوث في إعدادات الهاتف');
    });

    test('a print-data failure never leaves the job stuck on "printing"', () async {
      final (m, _) = await _manager();
      expect(await m.printInvoice(7, () async => throw Exception('network')), isFalse);
      expect(m.isPrinting, isFalse);
      expect(m.lastJob!.status, PrintJobStatus.failed);
    });
  });

  group('PrintJobStatusBar', () {
    testWidgets('shows جاري الطباعة… then success; on failure offers إعادة الطباعة + اختيار طابعة', (tester) async {
      final (m, printer) = await _manager();
      await sl.reset();
      sl.registerSingleton<PrinterManager>(m);
      addTearDown(sl.reset);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PrintJobStatusBar())));
      expect(find.byType(Container), findsNothing);

      printer.holdPrint = Completer<void>();
      final job = m.printInvoice(7, () async => _data());
      await tester.pump();
      expect(find.text('جاري الطباعة…'), findsOneWidget);
      printer.holdPrint!.complete();
      await job;
      await tester.pump();
      expect(find.text('تمت الطباعة'), findsOneWidget);

      printer
        ..holdPrint = null
        ..outcome = PrintOutcome.interrupted;
      await m.printInvoice(8, () async => _data());
      await tester.pump();
      expect(find.byKey(const Key('print-status-failed')), findsOneWidget);
      expect(find.textContaining('الفاتورة محفوظة'), findsOneWidget);
      expect(find.text('إعادة الطباعة'), findsOneWidget);
      expect(find.text('اختيار طابعة'), findsOneWidget);

      printer.outcome = PrintOutcome.success;
      await tester.tap(find.text('إعادة الطباعة'));
      await tester.pump();
      await tester.pump();
      expect(find.text('تمت الطباعة'), findsOneWidget);
      expect(printer.printCalls, 3);
    });
  });
}
