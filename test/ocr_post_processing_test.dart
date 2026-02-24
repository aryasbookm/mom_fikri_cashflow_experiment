import 'package:flutter_test/flutter_test.dart';
import 'package:mom_fikri_cashflow/models/ocr_transaction_draft.dart';
import 'package:mom_fikri_cashflow/services/ai_providers/ocr_post_processing.dart';

void main() {
  group('OcrPostProcessor.normalize', () {
    test('applies compound math parser and cleans trailing amount tokens', () {
      final batch = OcrBatchDraft.fromJson({
        'is_transaction': true,
        'reason': '',
        'summary': {'date_detected': '2025-11-04', 'notes_found': []},
        'ignored_lines': [],
        'transactions': [
          {
            'is_transaction': true,
            'type': 'IN',
            'amount': 10000,
            'description': 'Sosis 10.000 + 5.000',
            'category_hint': 'Penjualan Kue',
            'date_iso': '2025-11-04',
            'date_source': 'explicit',
            'confidence': 90,
            'raw_text': 'Sosis 10.000 + 5.000',
            'needs_review': false,
            'warning': '',
          },
        ],
      });

      final result = OcrPostProcessor.normalize(
        batch: batch,
        maxItems: 30,
        forceReview: false,
      );

      expect(result.transactions.length, 1);
      expect(result.transactions.first.amount, 15000);
      expect(result.transactions.first.description, 'Sosis');
      expect(result.transactions.first.needsReview, isTrue);
      expect(
        result.transactions.first.warning,
        contains('Nominal gabungan dihitung otomatis oleh parser lokal.'),
      );
    });

    test('filters summary-like lines into ignored and notes', () {
      final batch = OcrBatchDraft.fromJson({
        'is_transaction': true,
        'reason': '',
        'summary': {'date_detected': '', 'notes_found': []},
        'ignored_lines': [],
        'transactions': [
          {
            'is_transaction': true,
            'type': 'IN',
            'amount': 184000,
            'description': 'Uang Bersih',
            'category_hint': '',
            'date_iso': '',
            'date_source': 'unknown',
            'confidence': 80,
            'raw_text': 'Uang Bersih 184.000',
            'needs_review': false,
            'warning': '',
          },
        ],
      });

      final result = OcrPostProcessor.normalize(
        batch: batch,
        maxItems: 30,
        forceReview: false,
      );

      expect(result.transactions, isEmpty);
      expect(result.notesFound, contains('Uang Bersih 184.000'));
      expect(result.ignoredLines, contains('Uang Bersih 184.000'));
    });

    test('handles chained math expressions deterministically', () {
      final batch = OcrBatchDraft.fromJson({
        'is_transaction': true,
        'reason': '',
        'summary': {'date_detected': '2025-11-04', 'notes_found': []},
        'ignored_lines': [],
        'transactions': [
          {
            'is_transaction': true,
            'type': 'IN',
            'amount': 10000,
            'description': 'Donat 10.000 + 5.000 + 2.000',
            'category_hint': 'Penjualan Kue',
            'date_iso': '2025-11-04',
            'date_source': 'explicit',
            'confidence': 88,
            'raw_text': 'Donat 10.000 + 5.000 + 2.000',
            'needs_review': false,
            'warning': '',
          },
        ],
      });

      final result = OcrPostProcessor.normalize(
        batch: batch,
        maxItems: 30,
        forceReview: false,
      );

      expect(result.transactions.length, 1);
      expect(result.transactions.first.amount, 17000);
      expect(result.transactions.first.description, 'Donat');
      expect(result.transactions.first.needsReview, isTrue);
      expect(
        result.transactions.first.warning,
        contains('Nominal gabungan dihitung otomatis oleh parser lokal.'),
      );
    });

    test(
      'keeps inferred date transactions with mandatory review semantics',
      () {
        final batch = OcrBatchDraft.fromJson({
          'is_transaction': true,
          'reason': '',
          'summary': {'date_detected': '', 'notes_found': []},
          'ignored_lines': [],
          'transactions': [
            {
              'is_transaction': true,
              'type': 'IN',
              'amount': 50000,
              'description': 'Bolu',
              'category_hint': 'Penjualan Kue',
              'date_iso': '',
              'date_source': 'inferred',
              'confidence': 70,
              'raw_text': 'Bolu 50.000',
              'needs_review': false,
              'warning': '',
            },
          ],
        });

        final result = OcrPostProcessor.normalize(
          batch: batch,
          maxItems: 30,
          forceReview: false,
        );

        expect(result.transactions.length, 1);
        expect(result.transactions.first.dateSource, 'inferred');
        expect(result.transactions.first.needsReview, isTrue);
        expect(
          result.transactions.first.warning,
          contains(
            'Tanggal diinferensi dari konteks, mohon konfirmasi manual.',
          ),
        );
      },
    );

    test('respects maxItems cap for large OCR payload', () {
      final transactions = List.generate(35, (index) {
        return {
          'is_transaction': true,
          'type': 'IN',
          'amount': 10000 + index,
          'description': 'Item $index',
          'category_hint': 'Penjualan Kue',
          'date_iso': '2025-11-04',
          'date_source': 'explicit',
          'confidence': 90,
          'raw_text': 'Item $index ${(10000 + index).toString()}',
          'needs_review': false,
          'warning': '',
        };
      });

      final batch = OcrBatchDraft.fromJson({
        'is_transaction': true,
        'reason': '',
        'summary': {'date_detected': '2025-11-04', 'notes_found': []},
        'ignored_lines': [],
        'transactions': transactions,
      });

      final result = OcrPostProcessor.normalize(
        batch: batch,
        maxItems: 30,
        forceReview: false,
      );

      expect(result.transactions.length, 30);
    });
  });
}
