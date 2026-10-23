import 'dart:convert';
import 'dart:io';

import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';
import 'package:alkhair_mobileapp/features/admin/presentation/widgets/batch_number_panel.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/report_models.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/delegate_reports_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixtures are REAL responses of the backend endpoints (captured from the
/// isolated test DB through the actual controllers, 2026-10-23):
///  - manufacturing_start.json          POST /manufacturing (بدء تشغيلة)
///  - manufacturing_show_completed.json GET /manufacturing/{id} after استلام
///    إنتاج تام with a packaging line
///  - customer_debts_page.json          GET /v1/mobile/admin/reports/customer-debts?per_page=1
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('production batch number', () {
    test('start response carries the printable batch number and coding lines', () {
      final d = ProductionBatchDetailModel.fromJson(_fixture('manufacturing_start.json'));
      expect(d.batchNumber, '261012-01');
      expect(d.runNumber, 'BATCH-2026-0001');
      expect(d.productionDate, '2026-10-12');
      expect(d.label, '261012-01');
      expect(d.codingLines.map((c) => c.line),
          ['PRD 12/10/26  EXP 12/04/27  B:261012-01', 'PRD 12/10/26  B:261012-01']);
    });

    test('detail parses per-output expiry, creator and packaging lines', () {
      final d = ProductionBatchDetailModel.fromJson(_fixture('manufacturing_show_completed.json'));
      expect(d.status, 'completed');
      expect(d.createdByName, 'Admin');
      expect(d.outputs.map((o) => o.expiryDate), ['2027-04-12', null]);
      expect(d.materials.where((m) => m.itemType == 'packaging').single.materialName, 'علبة 1 ك');
    });

    test('batch card payload: number, dates, coding line per output, packaging section', () {
      final card = batchCardExportData(ProductionBatchDetailModel.fromJson(_fixture('manufacturing_show_completed.json')));
      expect(card.batchNumber, '261012-01');
      expect(card.meta.first, ['رقم التشغيلة', 'BATCH-2026-0001']);
      expect(card.meta[1], ['تاريخ الإنتاج', '12/10/2026']);
      expect(card.outputRows.first, ['جبن رومي', '12/04/2027', '95 كيلو', 'PRD 12/10/26  EXP 12/04/27  B:261012-01']);
      expect(card.outputRows.last[1], '—', reason: 'no shelf life → no expiry');
      expect(card.materialRows, [
        ['1', 'لبن خام', '100', 'كيلو'],
      ]);
      expect(card.packagingRows, [
        ['1', 'علبة 1 ك', '95', 'علبة'],
      ]);
    });

    test('old runs (no batch number) show "—" and fall back to the run number in lists', () {
      final old = ProductionBatchSummaryModel.fromJson({
        'id': 7, 'batch_number': null, 'run_number': 'BATCH-2026-0007', 'status': 'completed',
        'created_at': '2026-08-05T01:54:36.000000Z', 'recipe': {'name': 'جبن قريش', 'category': null},
      });
      expect(batchNumberLabel(old.batchNumber), '—');
      expect(old.label, 'BATCH-2026-0007');
      // Pre-rename payload (no run_number at all) still renders.
      final legacy = ProductionBatchSummaryModel.fromJson({
        'id': 3, 'batch_number': null, 'status': 'completed', 'created_at': null, 'recipe': null,
      });
      expect(legacy.label, '#3');
    });
  });

  group('مديونيات العملاء', () {
    test('page model keeps the global rank and the all-debtor summary', () {
      final r = CustomerDebtsReportModel.fromJson(_fixture('customer_debts_page.json'));
      expect(r.rows.single.rank, 1);
      expect(r.rows.single.name, 'سوبر ماركت النور');
      expect(r.currentPage, 1);
      expect(r.lastPage, 2);
      expect(r.customerCount, 2);
      expect(r.totalDebt, 2830.5);
    });

    test('export payload is black & white with 2-decimal amounts and the grand total last', () {
      final data = customerDebtsExportData(CustomerDebtsReportModel.fromJson(_fixture('customer_debts_page.json')));
      expect(data.monochrome, isTrue);
      expect(data.headers, ['#', 'العميل', 'الهاتف', 'المنطقة', 'المديونية', 'آخر حركة']);
      expect(data.rows.single, ['1', 'سوبر ماركت النور', '01001234567', '-', '2,450.50', '-']);
      expect(data.totals, ['', 'الإجمالي — 2 عميل', '', '', '2,830.50', '']);
      expect(data.summaryLines, ['عدد العملاء المدينين: 2']);
    });
  });
}
