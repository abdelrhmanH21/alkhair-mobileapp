import 'package:alkhair_mobileapp/features/admin/data/datasources/admin_remote_datasource.dart';
import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';
import 'package:alkhair_mobileapp/features/admin/presentation/widgets/reference_prices_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// "الأسعار المرجعية" admin tab: read-only list (price effective today +
/// "ساري من", missing-price marker), "تعديل سعر منتج" with searchable
/// product, Arabic-digit price, "ابتداءً من" date, preview before confirm,
/// past-date warning, and "سجل الأسعار" with delete.

class _FakeRemote implements AdminRemoteDataSource {
  List<ReferencePriceProductModel> rows;
  ReferencePriceChangeResult previewResult = const ReferencePriceChangeResult(
    invoicesRecalculated: 0, balanceBefore: 10, balanceAfter: 10,
  );
  final previews = <Map<String, Object>>[];
  final creates = <Map<String, Object>>[];
  final deletes = <int>[];
  int fetches = 0;

  _FakeRemote(this.rows);

  @override
  Future<List<ReferencePriceProductModel>> fetchReferencePrices(int repId) async {
    fetches++;
    return rows;
  }

  @override
  Future<ReferencePriceChangeResult> previewReferencePrice({
    required int repId, required int productId, required double referencePrice, required String effectiveFrom,
  }) async {
    previews.add({'product': productId, 'price': referencePrice, 'from': effectiveFrom});
    return previewResult;
  }

  @override
  Future<ReferencePriceChangeResult> createReferencePrice({
    required int repId, required int productId, required double referencePrice, required String effectiveFrom,
  }) async {
    creates.add({'product': productId, 'price': referencePrice, 'from': effectiveFrom});
    return const ReferencePriceChangeResult(invoicesRecalculated: 0, balanceBefore: 10, balanceAfter: 10, message: 'تم حفظ السعر المرجعي الجديد.');
  }

  @override
  Future<ReferencePriceChangeResult> deleteReferencePrice({required int repId, required int versionId}) async {
    deletes.add(versionId);
    return const ReferencePriceChangeResult(invoicesRecalculated: 1, balanceBefore: 10, balanceAfter: 5, message: 'تم حذف السعر وإعادة احتساب 1 فاتورة.');
  }

  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

ReferencePriceProductModel _cheese() => ReferencePriceProductModel.fromJson({
      'product_id': 1, 'product_name': 'جبن رومي', 'unit': 'kg', 'has_price': true,
      'reference_price': 20, 'effective_from': null, 'next_change': null,
      'versions': [
        {'id': 11, 'reference_price': 20, 'effective_from': null, 'created_by': {'id': 1, 'name': 'Admin'}, 'created_at': '2026-10-01T10:00:00'},
      ],
    });

ReferencePriceProductModel _milk() => ReferencePriceProductModel.fromJson({
      'product_id': 2, 'product_name': 'لبن', 'unit': 'l', 'has_price': false,
      'reference_price': null, 'effective_from': null, 'next_change': null, 'versions': [],
    });

final _today = DateTime(2026, 10, 26, 9);

Future<void> _pump(WidgetTester tester, _FakeRemote remote) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: ReferencePricesTab(remote: remote, repId: 9, now: () => _today)),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pickProductAndPrice(WidgetTester tester, String search, String productName, String price) async {
  await tester.tap(find.text('تعديل سعر منتج'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('ref-price-search')), search);
  await tester.pump();
  await tester.tap(find.text(productName).last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('ref-price-value')), price);
  await tester.pump(const Duration(milliseconds: 450)); // preview debounce
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('read-only list: price effective today, "ساري من", missing marker, no inline editing', (tester) async {
    final remote = _FakeRemote([_cheese(), _milk()]);
    await _pump(tester, remote);

    expect(find.text('جبن رومي'), findsOneWidget);
    expect(find.text('20.00'), findsOneWidget);
    expect(find.text('ساري من: منذ البداية'), findsOneWidget);
    expect(find.text('لم يُحدد سعر'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'no inline editing in the list');
    expect(find.byTooltip('سجل الأسعار'), findsOneWidget, reason: 'only products with versions have a history');
  });

  testWidgets('edit: search, Arabic-digit price, default today, "no past invoice changes" preview, confirm', (tester) async {
    final remote = _FakeRemote([_cheese(), _milk()]);
    await _pump(tester, remote);

    await _pickProductAndPrice(tester, 'رومي', 'جبن رومي', '٣٥٫٥');

    expect(find.text('2026-10-26'), findsOneWidget, reason: 'ابتداءً من defaults to today');
    expect(find.textContaining('تاريخ في الماضي'), findsNothing);
    expect(remote.previews.last, {'product': 1, 'price': 35.5, 'from': '2026-10-26'});
    expect(find.text('لن تتغير أي فاتورة سابقة، ولن يتغير المستحق.'), findsOneWidget);
    expect(remote.creates, isEmpty, reason: 'preview never saves');

    await tester.tap(find.text('تأكيد الحفظ'));
    await tester.pumpAndSettle();
    expect(remote.creates.single, {'product': 1, 'price': 35.5, 'from': '2026-10-26'});
    expect(find.text('تأكيد الحفظ'), findsNothing, reason: 'sheet closed');
    expect(remote.fetches, 2, reason: 'list reloaded after save');
  });

  testWidgets('a past "ابتداءً من" shows the warning and the affected-invoices preview', (tester) async {
    final remote = _FakeRemote([_cheese(), _milk()])
      ..previewResult = const ReferencePriceChangeResult(
        invoicesRecalculated: 2, dateFrom: '2026-10-20', dateTo: '2026-10-24',
        balanceBefore: 200, balanceAfter: 170, retroactive: true,
      );
    await _pump(tester, remote);
    await _pickProductAndPrice(tester, 'جبن', 'جبن رومي', '110');

    await tester.tap(find.byKey(const Key('ref-price-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(find.text('2026-10-20'), findsOneWidget);
    expect(find.textContaining('تاريخ في الماضي'), findsOneWidget);
    expect(remote.previews.last['from'], '2026-10-20');
    expect(find.text('سيُعاد احتساب 2 فاتورة سابقة (من 2026-10-20 إلى 2026-10-24). المستحق: 200.00 ← 170.00'), findsOneWidget);
  });

  testWidgets('more than 2 decimals is not accepted (no preview, confirm disabled)', (tester) async {
    final remote = _FakeRemote([_cheese()]);
    await _pump(tester, remote);
    await _pickProductAndPrice(tester, '', 'جبن رومي', '10.123');

    expect(remote.previews, isEmpty);
    final confirm = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'تأكيد الحفظ'));
    expect(confirm.onPressed, isNull);
  });

  testWidgets('سجل الأسعار: delete a version after confirming', (tester) async {
    final remote = _FakeRemote([_cheese()]);
    await _pump(tester, remote);

    await tester.tap(find.byTooltip('سجل الأسعار'));
    await tester.pumpAndSettle();
    expect(find.text('20.00 — ساري من منذ البداية'), findsOneWidget);
    expect(find.textContaining('بواسطة Admin'), findsOneWidget);

    await tester.tap(find.byTooltip('حذف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(remote.deletes, isEmpty, reason: 'cancel deletes nothing');

    await tester.tap(find.byTooltip('حذف'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(remote.deletes, [11]);
    expect(find.text('لا توجد أسعار.'), findsOneWidget);
  });
}
