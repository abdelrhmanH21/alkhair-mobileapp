import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';

/// Covers DistributorTransactionModel/DistributorModel JSON parsing against
/// AdminDistributorController's actual response shape — in particular that
/// decimal-cast columns (Laravel serializes `decimal` casts as JSON
/// strings, e.g. "150.00") parse correctly via _asDouble(), and that
/// isGoods correctly distinguishes goods_issued/goods_returned from
/// payment (used throughout distributor_detail_page.dart to decide which
/// edit sheet a tapped statement row opens).
void main() {
  group('DistributorModel.fromJson', () {
    test('parses a decimal-cast running_balance string correctly', () {
      final model = DistributorModel.fromJson({
        'id': 1,
        'name': 'طارق',
        'phone': '0100000000',
        'notes': null,
        'running_balance': '150.50',
      });
      expect(model.runningBalance, 150.50);
      expect(model.name, 'طارق');
    });
  });

  group('DistributorTransactionModel.fromJson', () {
    test('goods_issued transaction parses items, amount and balance_after as doubles', () {
      final model = DistributorTransactionModel.fromJson({
        'id': 10,
        'type': 'goods_issued',
        'transaction_date': '2026-09-01T00:00:00.000000Z',
        'amount': '200.00',
        'balance_after': '200.00',
        'notes': null,
        'warehouse': {'id': 5, 'name': 'مخزن المنتجات'},
        'treasury': null,
        'created_by': {'id': 2, 'name': 'Admin'},
        'items': [
          {
            'product_id': 7,
            'quantity': '10.000',
            'unit_price': '20.00',
            'subtotal': '200.00',
            'product': {'id': 7, 'name': 'لبن', 'unit': 'كرتونة'},
          },
        ],
      });

      expect(model.isGoods, isTrue);
      expect(model.transactionDate, '2026-09-01');
      expect(model.amount, 200.0);
      expect(model.balanceAfter, 200.0);
      expect(model.items, hasLength(1));
      expect(model.items.first.productName, 'لبن');
      expect(model.items.first.quantity, 10.0);
      expect(model.items.first.unitPrice, 20.0);
      expect(model.createdByName, 'Admin');
    });

    test('payment transaction is not isGoods and carries treasury info', () {
      final model = DistributorTransactionModel.fromJson({
        'id': 11,
        'type': 'payment',
        'transaction_date': '2026-09-02',
        'amount': '50.00',
        'balance_after': '150.00',
        'notes': 'دفعة نقدية',
        'warehouse': null,
        'treasury': {'id': 3, 'name': 'الخزينة الرئيسية'},
        'created_by': null,
        'items': [],
      });

      expect(model.isGoods, isFalse);
      expect(model.treasuryId, 3);
      expect(model.treasuryName, 'الخزينة الرئيسية');
      expect(model.notes, 'دفعة نقدية');
      expect(model.items, isEmpty);
    });
  });

  group('DistributorStatementModel.fromJson', () {
    test('parses distributor + a chronological list of transactions', () {
      final model = DistributorStatementModel.fromJson({
        'distributor': {'id': 1, 'name': 'طارق', 'phone': null, 'notes': null, 'running_balance': '90.00'},
        'transactions': [
          {
            'id': 1, 'type': 'goods_issued', 'transaction_date': '2026-09-01', 'amount': '300.00',
            'balance_after': '300.00', 'notes': null, 'warehouse': null, 'treasury': null,
            'created_by': null, 'items': [],
          },
          {
            'id': 2, 'type': 'payment', 'transaction_date': '2026-09-01', 'amount': '210.00',
            'balance_after': '90.00', 'notes': null, 'warehouse': null,
            'treasury': {'id': 1, 'name': 'الخزينة'}, 'created_by': null, 'items': [],
          },
        ],
      });

      expect(model.distributor.runningBalance, 90.0);
      expect(model.transactions, hasLength(2));
      expect(model.transactions.last.balanceAfter, 90.0);
    });
  });
}
