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

    test('normalizes duplicated amount tokens like 20.00020.000', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': '20.00020.000',
            'description': 'Donat',
            'category_hint': 'Snack',
            'date_iso': '2025-11-04',
            'date_source': 'explicit',
            'needs_review': false,
            'warning': '',
            'confidence': 90,
          },
        ],
      });

      expect(draft.transactions.length, 1);
      expect(draft.transactions.first.amount, 20000);
    });

    test('infers dates deterministically for blocks around explicit date', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': 40000,
            'description': 'Subek, manis',
            'category_hint': 'Penjualan Kue',
            'date_iso': '',
            'date_source': 'unknown',
            'needs_review': false,
            'warning': '',
            'confidence': 80,
          },
          {
            'type': 'IN',
            'amount': 50000,
            'description': 'Tawar, bolu',
            'category_hint': 'Penjualan Kue',
            'date_iso': '2025-11-04',
            'date_source': 'explicit',
            'needs_review': false,
            'warning': '',
            'confidence': 90,
          },
          {
            'type': 'IN',
            'amount': 30000,
            'description': 'Donat',
            'category_hint': 'Penjualan Kue',
            'date_iso': '',
            'date_source': 'unknown',
            'needs_review': false,
            'warning': '',
            'confidence': 88,
          },
        ],
      });

      expect(draft.transactions.length, 3);
      expect(draft.transactions[0].dateIso, '2025-11-03');
      expect(draft.transactions[0].dateSource, 'inferred');
      expect(draft.transactions[0].needsReview, isTrue);
      expect(draft.transactions[2].dateIso, '2025-11-04');
      expect(draft.transactions[2].dateSource, 'inferred');
      expect(draft.transactions[2].needsReview, isTrue);
    });

    test('falls back to today when no date exists at all', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': 20000,
            'description': 'Donat',
            'category_hint': 'Penjualan Kue',
            'date_iso': '',
            'date_source': 'unknown',
            'needs_review': false,
            'warning': '',
            'confidence': 80,
          },
        ],
      });

      expect(draft.transactions.length, 1);
      expect(draft.transactions.first.dateIso, isNotEmpty);
      expect(draft.transactions.first.dateSource, 'inferred');
      expect(draft.transactions.first.needsReview, isTrue);
      expect(
        draft.inferenceNotes.join(' ').toLowerCase(),
        contains('fallback'),
      );
    });
  });
}
