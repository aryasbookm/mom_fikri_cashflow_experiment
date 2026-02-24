import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_fikri_cashflow/services/chat_import_audit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatImportAuditService', () {
    test('detects duplicate hash within configured window', () async {
      SharedPreferences.setMockInitialValues({});

      await ChatImportAuditService.recordSaved(
        hash: 'abc123',
        itemCount: 2,
        totalAmount: 30000,
      );

      final duplicate = await ChatImportAuditService.findRecentDuplicate(
        'abc123',
      );

      expect(duplicate, isNotNull);
      expect(duplicate!.hash, 'abc123');
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
        'chat_import_audit_records_v1': jsonEncode([
          {
            'hash': 'old-hash',
            'saved_at_ms': oldMs,
            'item_count': 1,
            'total_amount': 10000,
          },
        ]),
      });

      final duplicate = await ChatImportAuditService.findRecentDuplicate(
        'old-hash',
        windowHours: 72,
      );

      expect(duplicate, isNull);
    });
  });
}
