import 'dart:convert';

import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deleting a "مندوب حر السعر" settlement shortage from the فروقات الأسعار
/// ledger. Fixtures are REAL server output for rep #9 (طارق مصطفي) —
/// GET price-variance-statement before, and after DELETE
/// price-variance-transactions/18 (the −26,473.00 cash shortage from
/// settling loading #59), captured on 2026-10-01 inside a rolled-back
/// transaction.
const _before = '''{"rep": {"id": 9, "name": "طارق مصطفي", "price_variance_balance": -22938}, "transactions": [{"id": 4, "type": "accrual", "amount": 925, "balance_after": 925, "notes": null, "created_at": "2026-09-21T14:33:01.000000Z"}, {"id": 5, "type": "accrual", "amount": 695, "balance_after": 1620, "notes": null, "created_at": "2026-09-23T14:33:59.000000Z"}, {"id": 6, "type": "accrual", "amount": 980, "balance_after": 2600, "notes": null, "created_at": "2026-09-23T14:53:08.000000Z"}, {"id": 7, "type": "accrual", "amount": 705, "balance_after": 3305, "notes": null, "created_at": "2026-09-23T21:06:23.000000Z"}, {"id": 8, "type": "accrual", "amount": 500, "balance_after": 3805, "notes": null, "created_at": "2026-09-30T17:13:37.000000Z"}, {"id": 10, "type": "accrual", "amount": 655, "balance_after": 4460, "notes": null, "created_at": "2026-09-30T17:25:13.000000Z"}, {"id": 12, "type": "accrual", "amount": 740, "balance_after": 5200, "notes": null, "created_at": "2026-09-30T20:01:06.000000Z"}, {"id": 14, "type": "accrual", "amount": 535, "balance_after": 5735, "notes": null, "created_at": "2026-09-30T20:10:25.000000Z"}, {"id": 16, "type": "payout", "amount": -3000, "balance_after": 2735, "notes": null, "created_at": "2026-09-30T20:23:42.000000Z"}, {"id": 17, "type": "accrual", "amount": 800, "balance_after": 3535, "notes": null, "created_at": "2026-09-30T20:46:59.000000Z"}, {"id": 18, "type": "penalty", "amount": -26473, "balance_after": -22938, "notes": "جزاء — عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #59", "created_at": "2026-09-30T21:22:33.000000Z"}]}''';
const _after = '''{"rep": {"id": 9, "name": "طارق مصطفي", "price_variance_balance": 3535}, "transactions": [{"id": 4, "type": "accrual", "amount": 925, "balance_after": 925, "notes": null, "created_at": "2026-09-21T14:33:01.000000Z"}, {"id": 5, "type": "accrual", "amount": 695, "balance_after": 1620, "notes": null, "created_at": "2026-09-23T14:33:59.000000Z"}, {"id": 6, "type": "accrual", "amount": 980, "balance_after": 2600, "notes": null, "created_at": "2026-09-23T14:53:08.000000Z"}, {"id": 7, "type": "accrual", "amount": 705, "balance_after": 3305, "notes": null, "created_at": "2026-09-23T21:06:23.000000Z"}, {"id": 8, "type": "accrual", "amount": 500, "balance_after": 3805, "notes": null, "created_at": "2026-09-30T17:13:37.000000Z"}, {"id": 10, "type": "accrual", "amount": 655, "balance_after": 4460, "notes": null, "created_at": "2026-09-30T17:25:13.000000Z"}, {"id": 12, "type": "accrual", "amount": 740, "balance_after": 5200, "notes": null, "created_at": "2026-09-30T20:01:06.000000Z"}, {"id": 14, "type": "accrual", "amount": 535, "balance_after": 5735, "notes": null, "created_at": "2026-09-30T20:10:25.000000Z"}, {"id": 16, "type": "payout", "amount": -3000, "balance_after": 2735, "notes": null, "created_at": "2026-09-30T20:23:42.000000Z"}, {"id": 17, "type": "accrual", "amount": 800, "balance_after": 3535, "notes": null, "created_at": "2026-09-30T20:46:59.000000Z"}]}''';

PriceVarianceStatementModel _parse(String s) =>
    PriceVarianceStatementModel.fromJson(jsonDecode(s) as Map<String, dynamic>);

void _expectConsistentChain(PriceVarianceStatementModel s) {
  var running = 0.0;
  for (final tx in s.transactions) {
    running = double.parse((running + tx.amount).toStringAsFixed(2));
    expect(tx.balanceAfter, running, reason: 'row #${tx.id} (${tx.type})');
  }
  expect(s.priceVarianceBalance, running);
}

void main() {
  test('only سلفة/جزاء/مكافأة rows are deletable — never accruals or payouts', () {
    final s = _parse(_before);
    final deletable = s.transactions.where((t) => t.isDeletable).toList();
    expect(deletable.map((t) => t.id), [18]);
    expect(deletable.single.type, 'penalty');
    expect(deletable.single.notes, contains('عجز نقدي عند التسوية'));
    expect(s.transactions.where((t) => t.type == 'payout').every((t) => !t.isDeletable), isTrue);
    expect(s.transactions.where((t) => t.isAccrual).every((t) => !t.isDeletable), isTrue);
  });

  test('before: the shortage takes the balance from 3535.00 to −22938.00', () {
    final s = _parse(_before);
    _expectConsistentChain(s);
    expect(s.transactions.last.amount, -26473.0);
    expect(s.transactions[s.transactions.length - 2].balanceAfter, 3535.0);
    expect(s.priceVarianceBalance, -22938.0);
  });

  test('after delete: row gone, chain recomputed, balance as if it never existed', () {
    final before = _parse(_before);
    final after = _parse(_after);
    _expectConsistentChain(after);

    expect(after.transactions.map((t) => t.id), before.transactions.where((t) => t.id != 18).map((t) => t.id));
    for (final tx in after.transactions) {
      final orig = before.transactions.firstWhere((t) => t.id == tx.id);
      expect(tx.balanceAfter, orig.balanceAfter, reason: 'rows before the shortage keep their balance');
    }
    expect(after.priceVarianceBalance, 3535.0);
    expect(after.priceVarianceBalance - before.priceVarianceBalance, 26473.0);
  });
}
