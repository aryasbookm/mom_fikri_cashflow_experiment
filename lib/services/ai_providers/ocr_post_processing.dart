import '../../models/ocr_transaction_draft.dart';

class OcrPostProcessingResult {
  const OcrPostProcessingResult({
    required this.transactions,
    required this.notesFound,
    required this.ignoredLines,
  });

  final List<OcrTransactionDraft> transactions;
  final List<String> notesFound;
  final List<String> ignoredLines;
}

class OcrPostProcessor {
  static const _summaryKeywords = <String>[
    'total',
    'jumlah',
    'uang bersih',
    'bersih',
    'saldo akhir',
    'omset',
    'omzet',
  ];

  static const _knownBakeryWords = <String>[
    'donat',
    'roti',
    'sosis',
    'basreng',
    'brownis',
    'brownies',
    'bento',
    'kopi',
    'teh',
    'telor',
    'telur',
    'camilan',
    'cemilan',
    'maros',
    'abon',
    'kacang',
    'snack',
    'mabel',
    'mabal',
    'campur',
    'kue',
    'bolu',
  ];

  static const _ambiguousWords = <String>[
    'tcr',
    'tci',
    'tar',
    'maber',
    'madel',
    'mayed',
  ];

  static OcrPostProcessingResult normalize({
    required OcrBatchDraft batch,
    required int maxItems,
    required bool forceReview,
  }) {
    final normalized = <OcrTransactionDraft>[];
    final notes = <String>[...batch.notesFound];
    final ignored = <String>[...batch.ignoredLines];

    for (final item in batch.transactions) {
      final description = item.description.trim();
      final rawText = item.rawText.trim();

      if (item.amount <= 0 || description.length < 2) {
        continue;
      }

      if (_isSummaryLike(description, rawText, item.categoryHint)) {
        final noteSource = rawText.isNotEmpty ? rawText : description;
        if (noteSource.isNotEmpty) {
          notes.add(noteSource);
          ignored.add(noteSource);
        }
        continue;
      }

      final computedAmount = _computeCompoundAmount(
        rawText.isNotEmpty ? rawText : description,
      );
      final resolvedAmount = computedAmount ?? item.amount;

      final ambiguous = _looksAmbiguous(item);
      final needsReview = forceReview || item.needsReview || ambiguous;
      final warning =
          needsReview
              ? (item.warning.isNotEmpty
                  ? item.warning
                  : forceReview
                  ? 'AI belum yakin ini transaksi pasti, mohon review manual.'
                  : 'Tulisan/hasil OCR ambigu, mohon cek manual.')
              : '';

      normalized.add(
        OcrTransactionDraft(
          isTransaction: true,
          reason: item.reason,
          type: item.type,
          amount: resolvedAmount,
          description: item.description,
          categoryHint: item.categoryHint,
          dateIso: item.dateIso,
          confidence: item.confidence,
          rawText: item.rawText,
          needsReview: needsReview,
          warning: warning,
        ),
      );

      if (normalized.length >= maxItems) {
        break;
      }
    }

    return OcrPostProcessingResult(
      transactions: normalized,
      notesFound: _dedupe(notes),
      ignoredLines: _dedupe(ignored),
    );
  }

  static bool _isSummaryLike(
    String description,
    String rawText,
    String categoryHint,
  ) {
    final source = '$description $rawText $categoryHint'.toLowerCase();
    for (final keyword in _summaryKeywords) {
      if (source.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static bool _looksAmbiguous(OcrTransactionDraft item) {
    final description = item.description.toLowerCase().trim();
    final raw = item.rawText.toLowerCase().trim();
    final source = '$description $raw';

    for (final word in _ambiguousWords) {
      if (source.contains(word)) {
        return true;
      }
    }

    if (RegExp(r'[?]{1,}|[~]{1,}|[/]{2,}').hasMatch(source)) {
      return true;
    }

    if (description.length <= 3) {
      return true;
    }

    final words = description
        .split(RegExp(r'\s+|,'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return true;
    }

    final unknownShortWords =
        words.where((word) {
          if (word.length > 5) {
            return false;
          }
          return !_knownBakeryWords.contains(word);
        }).length;

    if (unknownShortWords >= 1) {
      return true;
    }

    return false;
  }

  static int? _computeCompoundAmount(String source) {
    final match = RegExp(r'(\d[\d., ]*(?:\+\s*\d[\d., ]*)+)').firstMatch(
      source,
    );
    if (match == null) {
      return null;
    }
    final expression = (match.group(1) ?? '').trim();
    if (expression.isEmpty) {
      return null;
    }

    var sum = 0;
    var count = 0;
    for (final part in expression.split('+')) {
      final value = _toIntRupiah(part);
      if (value != null && value > 0) {
        sum += value;
        count += 1;
      }
    }
    if (count < 2 || sum <= 0) {
      return null;
    }
    return sum;
  }

  static int? _toIntRupiah(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return null;
    }
    return int.tryParse(digits);
  }

  static List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in values) {
      final text = raw.trim();
      if (text.isEmpty) {
        continue;
      }
      if (seen.add(text)) {
        result.add(text);
      }
    }
    return result;
  }
}
