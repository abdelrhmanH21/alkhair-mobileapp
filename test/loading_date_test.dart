import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/admin/data/datasources/admin_remote_datasource.dart';
import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';

void main() {
  group('loading_date (تاريخ التوزيعة)', () {
    test('create payload carries a backdated loading_date as a local Y-m-d', () {
      final body = buildCreateLoadingPayload(
        delegateId: 4,
        warehouseId: 2,
        items: [{'product_id': 9, 'quantity': 10.0}],
        loadingDate: DateTime(2026, 9, 27, 23, 30), // late evening must not roll over
      );
      expect(body['loading_date'], '2026-09-27');
      expect(body['delegate_id'], 4);
    });

    test('omitting the date leaves it to the server default (today)', () {
      final body = buildCreateLoadingPayload(delegateId: 4, warehouseId: 2, items: const []);
      expect(body.containsKey('loading_date'), isFalse);
    });

    test('settlement-history row reads the loading business date, not settled_at', () {
      final r = SettlementRecordModel.fromJson({
        'id': 1,
        'loading_id': 41,
        'settled_at': '2026-09-30T18:00:00+03:00',
        'loading': {'id': 41, 'loading_date': '2026-09-27', 'created_at': '2026-09-30T09:00:00+03:00'},
        'expected_cash': 0, 'physical_cash': 0, 'cash_variance': 0, 'wallet_amount': 0,
        'cash_shortage_deduction': 0, 'stock_shortage_deduction': 0, 'damaged_goods_value': 0,
      });
      expect(r.loadingDate, '2026-09-27');
      expect(r.settledAt.day, 30);
    });

    test('falls back to created_at date for an un-backfilled loading', () {
      expect(loadingDateOf({'id': 41, 'loading_date': null, 'created_at': '2026-09-30T09:00:00+03:00'}), '2026-09-30');
      expect(loadingDateOf(null), isNull);
    });
  });
}
