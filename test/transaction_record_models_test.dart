import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/transaction_record_models.dart';

/// Expense.amount / PaymentCollection.amount are `decimal:2`-cast on the
/// backend, which serializes to JSON as a STRING — confirmed live against
/// production: GET /v1/mobile/delegate/expenses and
/// GET /v1/mobile/delegate/customer-collections for delegate #10's real
/// loading #16 returned exactly this shape (expense #11, collection #14,
/// both amount "10.00"). Before the fix, `json['amount'] as num?` threw a
/// TypeError on that string, silently emptying transactions_page.dart's
/// lists while the shift summary (which never round-trips through these
/// models) stayed correct.
void main() {
  test('ExpenseRecordModel.fromJson parses a real decimal-cast string amount', () {
    final json = {
      'id': 11,
      'category_id': null,
      'treasury_id': 1,
      'description': 'testo',
      'amount': '10.00',
      'expense_date': '2026-07-16T21:00:00.000000Z',
      'notes': null,
      'created_by': 10,
      'delegate_loading_id': 16,
      'created_at': '2026-07-17T05:50:38.000000Z',
      'updated_at': '2026-07-17T05:50:38.000000Z',
      'category': null,
    };

    final model = ExpenseRecordModel.fromJson(json);

    expect(model.id, 11);
    expect(model.description, 'testo');
    expect(model.amount, 10.0);
    expect(model.categoryName, isNull);
  });

  test('CustomerCollectionRecordModel.fromJson parses a real decimal-cast string amount', () {
    final json = {
      'id': 14,
      'type': 'collection',
      'customer_id': 19,
      'supplier_id': null,
      'milk_supplier_id': null,
      'treasury_id': 1,
      'amount': '10.00',
      'date': '2026-07-16T21:00:00.000000Z',
      'notes': null,
      'created_by': 10,
      'delegate_loading_id': 16,
      'created_at': '2026-07-17T05:50:50.000000Z',
      'updated_at': '2026-07-17T05:50:50.000000Z',
      'customer': {'id': 19, 'name': 'اسواق بدر'},
    };

    final model = CustomerCollectionRecordModel.fromJson(json);

    expect(model.id, 14);
    expect(model.customerId, 19);
    expect(model.customerName, 'اسواق بدر');
    expect(model.amount, 10.0);
  });

  test('still handles a plain numeric amount (e.g. if the backend cast ever changes)', () {
    final expenseJson = {
      'id': 99,
      'description': 'x',
      'amount': 15.5,
      'created_at': '2026-07-17T00:00:00.000000Z',
    };
    expect(ExpenseRecordModel.fromJson(expenseJson).amount, 15.5);
  });
}
