import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_fikri_cashflow/services/ocr_import_audit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OcrImportAuditService', () {
    test('detects duplicate hash within configured window', () async {
      SharedPreferences.setMockInitialValues({});

      await OcrImportAuditService.recordSaved(
        hash: 'ocr-hash',
        itemCount: 2,
        totalAmount: 30000,
      );

      final duplicate = await OcrImportAuditService.findRecentDuplicate(
        'ocr-hash',
      );

      expect(duplicate, isNotNull);
      expect(duplicate!.hash, 'ocr-hash');
      expect(duplicate.itemCount, 2);
      expect(duplicate.totalAmount, 30000);
    });

    test('ignores duplicate records outside configured window', () async {
      final oldMs =
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 80))
              .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'ocr_import_audit_records_v1': jsonEncode([
          {
            'hash': 'old-ocr-hash',
            'saved_at_ms': oldMs,
            'item_count': 1,
            'total_amount': 10000,
          },
        ]),
      });

      final duplicate = await OcrImportAuditService.findRecentDuplicate(
        'old-ocr-hash',
        windowHours: 72,
      );

      expect(duplicate, isNull);
    });

    test('returns null for non-matching hash even within window', () async {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'ocr_import_audit_records_v1': jsonEncode([
          {
            'hash': 'hash-a',
            'saved_at_ms': nowMs,
            'item_count': 3,
            'total_amount': 45000,
          },
        ]),
      });

      final duplicate = await OcrImportAuditService.findRecentDuplicate(
        'hash-b',
      );

      expect(duplicate, isNull);
    });
  });
}
