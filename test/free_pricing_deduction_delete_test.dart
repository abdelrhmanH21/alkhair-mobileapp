import 'dart:convert';

import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deleting rows from a "مندوب حر السعر" rep's فروقات الأسعار ledger.
/// Fixtures are REAL server output for rep #9 (طارق مصطفي, balance
/// −38,876.00) captured 2026-10-01 inside rolled-back transactions:
/// the statement before, after DELETE of penalty #20 (the −16,618 cash
/// shortage from loading #60, with #21 after it), and after DELETE of
/// payout #16 (−3,000, with 8 rows after it; its treasury was credited back).
const _before = '''{"rep": {"id": 9, "name": "طارق مصطفي", "price_variance_balance": -38876}, "transactions": [{"id": 4, "type": "accrual", "amount": 925, "balance_after": 925, "notes": null, "created_at": "2026-09-21T14:33:01.000000Z", "source_label": "فاتورة DINV-000068 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 5, "type": "accrual", "amount": 695, "balance_after": 1620, "notes": null, "created_at": "2026-09-23T14:33:59.000000Z", "source_label": "فاتورة DINV-000069 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 6, "type": "accrual", "amount": 980, "balance_after": 2600, "notes": null, "created_at": "2026-09-23T14:53:08.000000Z", "source_label": "فاتورة DINV-000070 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 7, "type": "accrual", "amount": 705, "balance_after": 3305, "notes": null, "created_at": "2026-09-23T21:06:23.000000Z", "source_label": "فاتورة DINV-000071 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 8, "type": "accrual", "amount": 500, "balance_after": 3805, "notes": null, "created_at": "2026-09-30T17:13:37.000000Z", "source_label": "فاتورة DINV-000072 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 10, "type": "accrual", "amount": 655, "balance_after": 4460, "notes": null, "created_at": "2026-09-30T17:25:13.000000Z", "source_label": "فاتورة DINV-000073 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 12, "type": "accrual", "amount": 740, "balance_after": 5200, "notes": null, "created_at": "2026-09-30T20:01:06.000000Z", "source_label": "فاتورة DINV-000074 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 14, "type": "accrual", "amount": 535, "balance_after": 5735, "notes": null, "created_at": "2026-09-30T20:10:25.000000Z", "source_label": "فاتورة DINV-000075 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 16, "type": "payout", "amount": -3000, "balance_after": 2735, "notes": null, "created_at": "2026-09-30T20:23:42.000000Z", "source_label": "صرف مستحقات من الخزينة الرئيسية", "source_date": null, "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}, {"id": 17, "type": "accrual", "amount": 800, "balance_after": 3535, "notes": null, "created_at": "2026-09-30T20:46:59.000000Z", "source_label": "فاتورة DINV-000076 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 18, "type": "penalty", "amount": -26473, "balance_after": -22938, "notes": "جزاء — عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #59", "created_at": "2026-09-30T21:22:33.000000Z", "source_label": "عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #59", "source_date": "2026-10-01", "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}, {"id": 19, "type": "accrual", "amount": 690, "balance_after": -22248, "notes": null, "created_at": "2026-09-30T21:48:09.000000Z", "source_label": "فاتورة DINV-000077 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 20, "type": "penalty", "amount": -16618, "balance_after": -38866, "notes": "جزاء — عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #60", "created_at": "2026-09-30T21:52:15.000000Z", "source_label": "عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #60", "source_date": "2026-10-01", "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}, {"id": 21, "type": "penalty", "amount": -10, "balance_after": -38876, "notes": "جزاء — 2", "created_at": "2026-09-30T21:52:49.000000Z", "source_label": "2", "source_date": "2026-10-29", "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}]}''';
const _afterPenalty20 = '''{"rep": {"id": 9, "name": "طارق مصطفي", "price_variance_balance": -22258}, "transactions": [{"id": 4, "type": "accrual", "amount": 925, "balance_after": 925, "notes": null, "created_at": "2026-09-21T14:33:01.000000Z", "source_label": "فاتورة DINV-000068 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 5, "type": "accrual", "amount": 695, "balance_after": 1620, "notes": null, "created_at": "2026-09-23T14:33:59.000000Z", "source_label": "فاتورة DINV-000069 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 6, "type": "accrual", "amount": 980, "balance_after": 2600, "notes": null, "created_at": "2026-09-23T14:53:08.000000Z", "source_label": "فاتورة DINV-000070 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 7, "type": "accrual", "amount": 705, "balance_after": 3305, "notes": null, "created_at": "2026-09-23T21:06:23.000000Z", "source_label": "فاتورة DINV-000071 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 8, "type": "accrual", "amount": 500, "balance_after": 3805, "notes": null, "created_at": "2026-09-30T17:13:37.000000Z", "source_label": "فاتورة DINV-000072 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 10, "type": "accrual", "amount": 655, "balance_after": 4460, "notes": null, "created_at": "2026-09-30T17:25:13.000000Z", "source_label": "فاتورة DINV-000073 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 12, "type": "accrual", "amount": 740, "balance_after": 5200, "notes": null, "created_at": "2026-09-30T20:01:06.000000Z", "source_label": "فاتورة DINV-000074 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 14, "type": "accrual", "amount": 535, "balance_after": 5735, "notes": null, "created_at": "2026-09-30T20:10:25.000000Z", "source_label": "فاتورة DINV-000075 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 16, "type": "payout", "amount": -3000, "balance_after": 2735, "notes": null, "created_at": "2026-09-30T20:23:42.000000Z", "source_label": "صرف مستحقات من الخزينة الرئيسية", "source_date": null, "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}, {"id": 17, "type": "accrual", "amount": 800, "balance_after": 3535, "notes": null, "created_at": "2026-09-30T20:46:59.000000Z", "source_label": "فاتورة DINV-000076 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 18, "type": "penalty", "amount": -26473, "balance_after": -22938, "notes": "جزاء — عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #59", "created_at": "2026-09-30T21:22:33.000000Z", "source_label": "عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #59", "source_date": "2026-10-01", "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}, {"id": 19, "type": "accrual", "amount": 690, "balance_after": -22248, "notes": null, "created_at": "2026-09-30T21:48:09.000000Z", "source_label": "فاتورة DINV-000077 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 21, "type": "penalty", "amount": -10, "balance_after": -22258, "notes": "جزاء — 2", "created_at": "2026-09-30T21:52:49.000000Z", "source_label": "2", "source_date": "2026-10-29", "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}]}''';
const _afterPayout16 = '''{"rep": {"id": 9, "name": "طارق مصطفي", "price_variance_balance": -35876}, "transactions": [{"id": 4, "type": "accrual", "amount": 925, "balance_after": 925, "notes": null, "created_at": "2026-09-21T14:33:01.000000Z", "source_label": "فاتورة DINV-000068 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 5, "type": "accrual", "amount": 695, "balance_after": 1620, "notes": null, "created_at": "2026-09-23T14:33:59.000000Z", "source_label": "فاتورة DINV-000069 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 6, "type": "accrual", "amount": 980, "balance_after": 2600, "notes": null, "created_at": "2026-09-23T14:53:08.000000Z", "source_label": "فاتورة DINV-000070 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 7, "type": "accrual", "amount": 705, "balance_after": 3305, "notes": null, "created_at": "2026-09-23T21:06:23.000000Z", "source_label": "فاتورة DINV-000071 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 8, "type": "accrual", "amount": 500, "balance_after": 3805, "notes": null, "created_at": "2026-09-30T17:13:37.000000Z", "source_label": "فاتورة DINV-000072 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 10, "type": "accrual", "amount": 655, "balance_after": 4460, "notes": null, "created_at": "2026-09-30T17:25:13.000000Z", "source_label": "فاتورة DINV-000073 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 12, "type": "accrual", "amount": 740, "balance_after": 5200, "notes": null, "created_at": "2026-09-30T20:01:06.000000Z", "source_label": "فاتورة DINV-000074 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 14, "type": "accrual", "amount": 535, "balance_after": 5735, "notes": null, "created_at": "2026-09-30T20:10:25.000000Z", "source_label": "فاتورة DINV-000075 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 17, "type": "accrual", "amount": 800, "balance_after": 6535, "notes": null, "created_at": "2026-09-30T20:46:59.000000Z", "source_label": "فاتورة DINV-000076 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 18, "type": "penalty", "amount": -26473, "balance_after": -19938, "notes": "جزاء — عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #59", "created_at": "2026-09-30T21:22:33.000000Z", "source_label": "عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #59", "source_date": "2026-10-01", "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}, {"id": 19, "type": "accrual", "amount": 690, "balance_after": -19248, "notes": null, "created_at": "2026-09-30T21:48:09.000000Z", "source_label": "فاتورة DINV-000077 — اختباري", "source_date": null, "deletable": false, "delete_blocked_reason": "فرق سعر ناتج عن فاتورة بيع — لا يُحذف إلا بتعديل الفاتورة نفسها.", "created_by": {"id": 27, "name": "طارق مصطفي"}}, {"id": 20, "type": "penalty", "amount": -16618, "balance_after": -35866, "notes": "جزاء — عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #60", "created_at": "2026-09-30T21:52:15.000000Z", "source_label": "عجز نقدي عند التسوية — المندوب: طارق مصطفي — التحميلة #60", "source_date": "2026-10-01", "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}, {"id": 21, "type": "penalty", "amount": -10, "balance_after": -35876, "notes": "جزاء — 2", "created_at": "2026-09-30T21:52:49.000000Z", "source_label": "2", "source_date": "2026-10-29", "deletable": true, "delete_blocked_reason": null, "created_by": {"id": 4, "name": "admin"}}]}''';

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

/// Replays [before] without row [removedId] — what the chain must be "as if
/// that entry had never existed".
Map<int, double> _counterfactual(PriceVarianceStatementModel before, int removedId) {
  var running = 0.0;
  return {
    for (final tx in before.transactions.where((t) => t.id != removedId))
      tx.id: running = double.parse((running + tx.amount).toStringAsFixed(2)),
  };
}

void main() {
  test('every type is listed with its source; all but invoice accruals are deletable', () {
    final s = _parse(_before);
    _expectConsistentChain(s);
    expect(s.priceVarianceBalance, -38876.0);

    for (final tx in s.transactions) {
      expect(tx.sourceLabel, isNotEmpty, reason: 'row #${tx.id}');
      expect(tx.isDeletable, !tx.isAccrual, reason: 'row #${tx.id} (${tx.type})');
      if (tx.isAccrual) {
        expect(tx.sourceLabel, startsWith('فاتورة DINV-'));
        expect(tx.deleteBlockedReason, contains('فاتورة'));
      }
    }
    final payout = s.transactions.firstWhere((t) => t.type == 'payout');
    expect(payout.sourceLabel, startsWith('صرف مستحقات من '));
    final shortage = s.transactions.firstWhere((t) => t.id == 20);
    expect(shortage.sourceLabel, contains('عجز نقدي عند التسوية'));
    expect(shortage.sourceDate, '2026-10-01');
  });

  test('deleting shortage penalty #20 mid-chain recomputes every later row', () {
    final before = _parse(_before);
    final after = _parse(_afterPenalty20);
    _expectConsistentChain(after);
    expect(after.transactions.any((t) => t.id == 20), isFalse);
    final expected = _counterfactual(before, 20);
    for (final tx in after.transactions) {
      expect(tx.balanceAfter, expected[tx.id], reason: 'row #${tx.id}');
    }
    expect(after.transactions.last.id, 21);
    expect(after.transactions.last.balanceAfter, -22258.0);
    expect(after.priceVarianceBalance, -22258.0);
  });

  test('deleting payout #16 recomputes the 8 later rows', () {
    final before = _parse(_before);
    final after = _parse(_afterPayout16);
    _expectConsistentChain(after);
    final expected = _counterfactual(before, 16);
    for (final tx in after.transactions) {
      expect(tx.balanceAfter, expected[tx.id], reason: 'row #${tx.id}');
    }
    expect(after.priceVarianceBalance, -35876.0);
    expect(after.priceVarianceBalance - before.priceVarianceBalance, 3000.0);
  });

  test('older responses without the deletable flag fall back to the type rule', () {
    final tx = PriceVarianceTransactionModel.fromJson(
        {'id': 1, 'type': 'payout', 'amount': -5, 'balance_after': 0, 'created_at': '2026-10-01T00:00:00Z'});
    expect(tx.isDeletable, isTrue);
    final accrual = PriceVarianceTransactionModel.fromJson(
        {'id': 2, 'type': 'accrual', 'amount': 5, 'balance_after': 5, 'created_at': '2026-10-01T00:00:00Z'});
    expect(accrual.isDeletable, isFalse);
  });
}
