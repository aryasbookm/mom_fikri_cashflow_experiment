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

      // Use description as primary source for compound math to avoid
      // accidentally combining numbers from unrelated raw OCR fragments.
      final amountSource = description;
      final computedAmount = _computeCompoundAmount(amountSource);
      final warningSuggestedAmount = _extractAmountHintFromWarning(
        item.warning,
      );
      final resolvedAmount =
          computedAmount ?? warningSuggestedAmount ?? item.amount;
      final cleanedDescription = _stripTrailingAmountTokens(description);
      final hasMathExpression = _containsMathExpression(amountSource);
      final shouldApplyMathWarning =
          (hasMathExpression &&
              computedAmount != null &&
              computedAmount > 0 &&
              computedAmount != item.amount) ||
          (warningSuggestedAmount != null &&
              warningSuggestedAmount > 0 &&
              warningSuggestedAmount != item.amount);

      final ambiguous = _looksAmbiguous(item);
      final needsReview =
          forceReview ||
          item.needsReview ||
          ambiguous ||
          shouldApplyMathWarning;
      final warning = _buildWarning(
        itemWarning: item.warning,
        needsReview: needsReview,
        forceReview: forceReview,
        ambiguous: ambiguous,
        shouldApplyMathWarning: shouldApplyMathWarning,
      );

      normalized.add(
        OcrTransactionDraft(
          isTransaction: true,
          reason: item.reason,
          type: item.type,
          amount: resolvedAmount,
          description:
              cleanedDescription.length >= 2 ? cleanedDescription : description,
          categoryHint: item.categoryHint,
          dateIso: item.dateIso,
          dateSource: item.dateSource,
          confidence: _normalizeConfidence(item),
          rawText: item.rawText,
          needsReview: needsReview,
          warning: warning,
        ),
      );

      if (normalized.length >= maxItems) {
        break;
      }
    }

    final filtered = _dropLikelyGrandTotalRows(
      rows: normalized,
      notesFound: notes,
      ignoredLines: ignored,
    );

    return OcrPostProcessingResult(
      transactions: filtered,
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

  static String _buildWarning({
    required String itemWarning,
    required bool needsReview,
    required bool forceReview,
    required bool ambiguous,
    required bool shouldApplyMathWarning,
  }) {
    if (!needsReview) {
      return '';
    }
    var warning = _localizeWarning(itemWarning.trim());
    if (warning.isEmpty) {
      if (forceReview) {
        warning = 'AI belum yakin ini transaksi pasti, mohon review manual.';
      } else if (ambiguous) {
        warning = 'Tulisan/hasil OCR ambigu, mohon cek manual.';
      }
    }
    if (shouldApplyMathWarning) {
      warning = _mergeWarnings(
        warning,
        'Nominal gabungan dihitung otomatis oleh parser lokal.',
      );
    }
    return warning;
  }

  static String _localizeWarning(String warning) {
    if (warning.isEmpty) {
      return warning;
    }
    var result = warning;
    final replacements = <MapEntry<String, String>>[
      const MapEntry(
        'Amount is not an integer rupiah.',
        'Nominal bukan bilangan rupiah utuh.',
      ),
      const MapEntry(
        'Category could not be determined.',
        'Kategori belum dapat ditentukan.',
      ),
      const MapEntry('Unknown', 'Tidak diketahui'),
      const MapEntry('Interpreted as', 'Diartikan sebagai'),
      const MapEntry(
        'but review is recommended.',
        'namun perlu ditinjau ulang.',
      ),
      const MapEntry('Ambiguous amount:', 'Nominal ambigu:'),
      const MapEntry('Ambiguous date:', 'Tanggal ambigu:'),
      const MapEntry('Needs review.', 'Perlu ditinjau ulang.'),
    ];
    for (final entry in replacements) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  static int _normalizeConfidence(OcrTransactionDraft item) {
    final heuristic = _heuristicConfidence(item);
    final modelConfidence = item.confidence.clamp(0, 100);
    if (modelConfidence <= 0) {
      return heuristic;
    }
    final warning = item.warning.trim().toLowerCase();
    var blended = ((modelConfidence * 0.45) + (heuristic * 0.55)).round();
    if (item.needsReview) {
      blended -= 6;
    }
    if (warning.contains('ambigu') || warning.contains('tidak diketahui')) {
      blended -= 6;
    }
    if (item.dateSource == 'explicit' &&
        !item.needsReview &&
        warning.isEmpty &&
        item.amount > 0 &&
        item.description.trim().length >= 4) {
      blended += 4;
    }
    return blended.clamp(35, 98);
  }

  static int _heuristicConfidence(OcrTransactionDraft item) {
    var score = 55;
    final desc = item.description.trim();
    final raw = item.rawText.trim();
    final warning = item.warning.trim().toLowerCase();

    if (item.amount > 0) {
      score += 15;
    }
    if (desc.length >= 4) {
      score += 12;
    } else if (desc.isNotEmpty) {
      score += 6;
    }
    if (raw.isNotEmpty) {
      score += 6;
    }
    if (item.type == 'IN' || item.type == 'OUT') {
      score += 5;
    }

    if (item.dateSource == 'explicit') {
      score += 8;
    } else if (item.dateSource == 'inferred') {
      score += 4;
    }

    if (item.needsReview) {
      score -= 10;
    }
    if (warning.isNotEmpty) {
      score -= 8;
    }
    if (warning.contains('ambigu') || warning.contains('tidak diketahui')) {
      score -= 7;
    }

    return score.clamp(35, 95);
  }

  static List<OcrTransactionDraft> _dropLikelyGrandTotalRows({
    required List<OcrTransactionDraft> rows,
    required List<String> notesFound,
    required List<String> ignoredLines,
  }) {
    if (rows.length <= 2) {
      return rows;
    }
    final summaryTotals = _extractSummaryTotals(<String>[
      ...notesFound,
      ...ignoredLines,
    ]);

    final totalAll = rows.fold<int>(0, (sum, row) => sum + row.amount);
    final result = <OcrTransactionDraft>[];
    for (final row in rows) {
      final desc = row.description.toLowerCase().trim();
      final genericDesc =
          desc == 'unknown' ||
          desc.contains('uang bersih') ||
          desc.contains('total') ||
          desc.contains('jumlah') ||
          desc.contains('saldo');
      final looksSummary = summaryTotals.contains(row.amount) && genericDesc;
      final looksOutlierGrandTotal = _looksLikeAccidentalGrandTotal(
        row: row,
        rows: rows,
        totalAll: totalAll,
      );
      final looksDetachedGrandTotal = _looksLikeDetachedGrandTotalRow(
        row: row,
        rows: rows,
        totalAll: totalAll,
      );
      if (!looksSummary &&
          !looksOutlierGrandTotal &&
          !looksDetachedGrandTotal) {
        result.add(row);
        continue;
      }
      final noteSource =
          row.rawText.trim().isNotEmpty
              ? row.rawText.trim()
              : row.description.trim();
      if (noteSource.isNotEmpty) {
        notesFound.add(noteSource);
        ignoredLines.add(noteSource);
      }
    }
    return result.isEmpty ? rows : result;
  }

  static bool _looksLikeAccidentalGrandTotal({
    required OcrTransactionDraft row,
    required List<OcrTransactionDraft> rows,
    required int totalAll,
  }) {
    if (rows.length < 6 || row.amount <= 0) {
      return false;
    }

    final amounts =
        rows.map((e) => e.amount).where((e) => e > 0).toList()..sort();
    if (amounts.length < 6) {
      return false;
    }

    final maxAmount = amounts.last;
    if (row.amount != maxAmount) {
      return false;
    }
    final secondMax = amounts[amounts.length - 2];
    if (secondMax <= 0) {
      return false;
    }

    // Candidate "total" should look abnormally larger than real item rows.
    if (row.amount < 120000 || row.amount < secondMax * 3) {
      return false;
    }

    final sumOthers = totalAll - row.amount;
    if (sumOthers <= 0) {
      return false;
    }

    // If the biggest amount is very close to sum of remaining rows,
    // it's likely a copied "grand total" accidentally parsed as a row.
    final delta = (row.amount - sumOthers).abs();
    final tolerance = ((sumOthers * 0.12).round()).clamp(5000, 80000);
    if (delta > tolerance) {
      return false;
    }

    // Usually appears with short/generic description from OCR noise.
    final desc = row.description.toLowerCase().trim();
    final descWords = desc.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return desc == 'unknown' || descWords.length <= 2;
  }

  static bool _looksLikeDetachedGrandTotalRow({
    required OcrTransactionDraft row,
    required List<OcrTransactionDraft> rows,
    required int totalAll,
  }) {
    if (rows.length < 5 || row.amount < 180000) {
      return false;
    }
    final amounts =
        rows.map((e) => e.amount).where((e) => e > 0).toList()..sort();
    if (amounts.length < 5 || row.amount != amounts.last) {
      return false;
    }
    final secondMax = amounts[amounts.length - 2];
    if (secondMax <= 0 || row.amount < (secondMax * 2.5)) {
      return false;
    }

    final raw = row.rawText.trim().toLowerCase();
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return false;
    }
    final hasLetters = RegExp(r'[a-z]').hasMatch(raw);
    final rawMostlyNumeric = !hasLetters || raw.length <= digits.length + 3;
    if (!rawMostlyNumeric) {
      return false;
    }

    final sumOthers = totalAll - row.amount;
    if (sumOthers <= 0) {
      return false;
    }
    final ratio = row.amount / sumOthers;
    if (ratio < 0.8 || ratio > 1.35) {
      return false;
    }

    final desc = row.description.toLowerCase().trim();
    final descWords =
        desc.split(RegExp(r'\s+|,')).where((w) => w.trim().isNotEmpty).length;
    if (desc == 'unknown' || descWords <= 2) {
      return true;
    }
    return false;
  }

  static Set<int> _extractSummaryTotals(List<String> lines) {
    final totals = <int>{};
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (!(lower.contains('total') ||
          lower.contains('jumlah') ||
          lower.contains('uang bersih') ||
          lower.contains('saldo'))) {
        continue;
      }
      final matches = RegExp(
        r'\d[\d.,\s]*(?:k|rb|ribu|jt|juta)?',
      ).allMatches(line).map((m) => m.group(0) ?? '');
      for (final token in matches) {
        final parsed = _toIntRupiah(token);
        if (parsed != null && parsed > 0) {
          totals.add(parsed);
        }
      }
    }
    return totals;
  }

  static String _mergeWarnings(String original, String extra) {
    final o = original.trim();
    final e = extra.trim();
    if (o.isEmpty) {
      return e;
    }
    if (e.isEmpty || o.toLowerCase().contains(e.toLowerCase())) {
      return o;
    }
    return '$o $e';
  }

  static bool _containsMathExpression(String sourceText) {
    return RegExp(r'\d[\d\.\,\s]*\+\s*\d').hasMatch(sourceText);
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

    final words =
        description
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
    final match = RegExp(
      r'(\d[\d., ]*(?:\+\s*\d[\d., ]*)+)',
    ).firstMatch(source);
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
    final raw = text.toLowerCase().trim();
    if (raw.isEmpty) {
      return null;
    }
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    final unitMatch = RegExp(
      r'^([0-9]+(?:[.,][0-9]+)?)(k|rb|ribu|jt|juta)$',
    ).firstMatch(compact);
    if (unitMatch != null) {
      final numberPart = unitMatch.group(1) ?? '';
      final unit = unitMatch.group(2) ?? '';
      final normalized = numberPart.replaceAll(',', '.');
      final value = double.tryParse(normalized);
      if (value == null) {
        return null;
      }
      final multiplier = (unit == 'jt' || unit == 'juta') ? 1000000 : 1000;
      return (value * multiplier).round();
    }

    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return null;
    }
    return int.tryParse(digits);
  }

  static int? _extractAmountHintFromWarning(String warningText) {
    final warning = warningText.trim();
    if (warning.isEmpty) {
      return null;
    }
    final lower = warning.toLowerCase();
    final markers = <String>[
      'interpreted as',
      'diartikan sebagai',
      'ditafsirkan sebagai',
      'menjadi',
    ];

    String? tail;
    for (final marker in markers) {
      final idx = lower.indexOf(marker);
      if (idx >= 0) {
        tail = warning.substring(idx + marker.length);
        break;
      }
    }
    tail ??= warning;

    final amountMatch = RegExp(r'\d[\d\.\,\s]{2,}').firstMatch(tail);
    if (amountMatch == null) {
      return null;
    }
    return _toIntRupiah(amountMatch.group(0) ?? '');
  }

  static String _stripTrailingAmountTokens(String description) {
    final cleaned = description.replaceFirst(
      RegExp(r'[\s\-:]*\d[\d\.\,\s]*(?:\+\s*\d[\d\.\,\s]*)*$'),
      '',
    );
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
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
