import 'package:flutter_test/flutter_test.dart';
import 'package:mom_fikri_cashflow/models/chat_import_draft.dart';

void main() {
  group('ChatImportDraftItem.fromJson', () {
    test('forces inferred date to needsReview with deterministic warning', () {
      final item = ChatImportDraftItem.fromJson({
        'type': 'IN',
        'amount': 50000,
        'description': 'Bolu',
        'category_hint': 'Bolu',
        'date_iso': '2025-11-03',
        'date_source': 'inferred',
        'needs_review': false,
        'warning': '',
        'confidence': 88,
      });

      expect(item.dateSource, 'inferred');
      expect(item.needsReview, isTrue);
      expect(
        item.warning,
        contains('Tanggal diinferensi dari konteks, mohon konfirmasi manual.'),
      );
    });
  });

  group('ChatImportDraft.fromJson', () {
    test('applies smart math parser and adds review warning', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': '10.000 + 5.000',
            'description': 'Sosis',
            'category_hint': 'Snack',
            'date_iso': '2025-11-03',
            'date_source': 'explicit',
            'needs_review': false,
            'warning': '',
            'confidence': 90,
          },
        ],
      });

      expect(draft.transactions.length, 1);
      expect(draft.transactions.first.amount, 15000);
      expect(draft.transactions.first.needsReview, isTrue);
      expect(
        draft.transactions.first.warning,
        contains('Nominal gabungan dihitung otomatis oleh parser lokal.'),
      );
    });

    test('filters non-transaction lines into ignoredLines', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': 184000,
            'description': 'Uang Bersih',
            'category_hint': '',
            'date_iso': '',
            'date_source': 'unknown',
            'needs_review': false,
            'warning': '',
            'confidence': 80,
          },
        ],
      });

      expect(draft.transactions, isEmpty);
      expect(draft.ignoredLines, contains('Uang Bersih'));
    });
  });
}
