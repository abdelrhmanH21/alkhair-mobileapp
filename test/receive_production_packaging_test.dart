import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/admin/data/datasources/admin_remote_datasource.dart';

void main() {
  group('buildCompleteProductionPayload (استلام إنتاج تام)', () {
    final outputs = [
      {'manufacturing_order_output_id': 7, 'actual_quantity': '120', 'warehouse_id': 3},
    ];

    test('sends packaging_materials alongside outputs, not instead of them', () {
      final body = buildCompleteProductionPayload(
        outputs: outputs,
        packagingMaterials: [
          {'raw_material_id': 38, 'quantity_used': '120'},
          {'raw_material_id': 51, 'quantity_used': '120'},
        ],
      );
      expect(body['outputs'], outputs);
      expect(body['packaging_materials'], [
        {'raw_material_id': 38, 'quantity_used': '120'},
        {'raw_material_id': 51, 'quantity_used': '120'},
      ]);
    });

    test('omits packaging_materials when none were entered', () {
      final body = buildCompleteProductionPayload(outputs: outputs, overheadFixed: 0);
      expect(body.containsKey('packaging_materials'), isFalse);
      expect(body.containsKey('overhead_fixed'), isFalse);
      expect(body['outputs'], outputs);
    });
  });
}
