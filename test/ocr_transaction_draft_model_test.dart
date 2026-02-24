import 'package:flutter_test/flutter_test.dart';
import 'package:mom_fikri_cashflow/models/ocr_transaction_draft.dart';

void main() {
  group('OcrTransactionDraft.fromJson', () {
    test('forces inferred date to needsReview with deterministic warning', () {
      final item = OcrTransactionDraft.fromJson({
        'is_transaction': true,
        'type': 'IN',
        'amount': 50000,
        'description': 'Bolu',
        'category_hint': 'Penjualan Kue',
        'date_iso': '2025-11-03',
        'date_source': 'inferred',
        'confidence': 91,
        'raw_text': 'Bolu 50.000',
        'needs_review': false,
        'warning': '',
      });

      expect(item.dateSource, 'inferred');
      expect(item.needsReview, isTrue);
      expect(
        item.warning,
        contains('Tanggal diinferensi dari konteks, mohon konfirmasi manual.'),
      );
    });

    test('normalizes invalid date_source to unknown', () {
      final item = OcrTransactionDraft.fromJson({
        'is_transaction': true,
        'type': 'IN',
        'amount': 10000,
        'description': 'Donat',
        'date_iso': '',
        'date_source': 'guessed',
        'confidence': 80,
        'raw_text': 'Donat 10.000',
        'needs_review': false,
        'warning': '',
      });

      expect(item.dateSource, 'unknown');
      expect(item.needsReview, isFalse);
    });
  });
}
