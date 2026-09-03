import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/loading_model.dart';

/// Covers the Part 5 (mid-shift loading top-up) additions to LoadingModel —
/// the JSON-parsing half of the confirm-before-stock-credit flow. The
/// actual stock-crediting logic is server-side (DelegateLoadingController
/// ::confirmAddition(), covered by
/// DelegatePriceBoundAndLoadingAdditionTest.php); this guards that the
/// mobile app correctly surfaces a pending addition from
/// GET /delegate/loading's response so the confirmation prompt can render.
void main() {
  group('LoadingModel — pendingAdditions (Part 5)', () {
    test('parses "additions" into pendingAdditions with their items', () {
      final loading = LoadingModel.fromJson({
        'id': 10,
        'delegate_id': 3,
        'warehouse_id': 1,
        'warehouse': {'name': 'مخزن المنتجات'},
        'status': 'accepted',
        'items': [],
        'additions': [
          {
            'id': 5,
            'loading_id': 10,
            'items': [
              {
                'id': 1,
                'product_id': 7,
                'product': {'name': 'لبن', 'unit': 'لتر'},
                'quantity': 20,
              },
            ],
          },
        ],
      });

      expect(loading.pendingAdditions, hasLength(1));
      final addition = loading.pendingAdditions.single;
      expect(addition.id, 5);
      expect(addition.loadingId, 10);
      expect(addition.items, hasLength(1));
      expect(addition.items.single.productName, 'لبن');
      expect(addition.items.single.productUnit, 'لتر');
      expect(addition.items.single.quantity, 20);
    });

    test('defaults pendingAdditions to empty when "additions" is absent (no pending top-up)', () {
      final loading = LoadingModel.fromJson({
        'id': 10,
        'delegate_id': 3,
        'warehouse_id': 1,
        'warehouse': {'name': 'مخزن المنتجات'},
        'status': 'accepted',
        'items': [],
      });

      expect(loading.pendingAdditions, isEmpty);
    });

    test('toJson() deliberately does NOT round-trip pendingAdditions (avoids a stale offline-cache prompt)', () {
      final loading = LoadingModel.fromJson({
        'id': 10,
        'delegate_id': 3,
        'warehouse_id': 1,
        'warehouse': {'name': 'مخزن المنتجات'},
        'status': 'accepted',
        'items': [],
        'additions': [
          {'id': 5, 'loading_id': 10, 'items': []},
        ],
      });

      final roundTripped = LoadingModel.fromJson(loading.toJson());
      expect(roundTripped.pendingAdditions, isEmpty);
    });
  });
}
