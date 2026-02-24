class ChatImportDraftItem {
  const ChatImportDraftItem({
    required this.type,
    required this.amount,
    required this.description,
    required this.categoryHint,
    required this.dateIso,
    required this.dateSource,
    required this.needsReview,
    required this.warning,
    required this.confidence,
  });

  final String type;
  final int amount;
  final String description;
  final String categoryHint;
  final String dateIso;
  final String dateSource; // explicit | inferred | unknown
  final bool needsReview;
  final String warning;
  final int confidence;

  ChatImportDraftItem copyWith({
    String? type,
    int? amount,
    String? description,
    String? categoryHint,
    String? dateIso,
    String? dateSource,
    bool? needsReview,
    String? warning,
    int? confidence,
  }) {
    return ChatImportDraftItem(
      type: type ?? this.type,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      categoryHint: categoryHint ?? this.categoryHint,
      dateIso: dateIso ?? this.dateIso,
      dateSource: dateSource ?? this.dateSource,
      needsReview: needsReview ?? this.needsReview,
      warning: warning ?? this.warning,
      confidence: confidence ?? this.confidence,
    );
  }

  factory ChatImportDraftItem.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? '').toString().trim().toUpperCase();
    final type = (rawType == 'IN' || rawType == 'OUT') ? rawType : 'IN';
    final amount = _toInt(json['amount']);
    final description = (json['description'] ?? '').toString().trim();
    final categoryHint = (json['category_hint'] ?? '').toString().trim();
    final dateIso = _normalizeDateIso((json['date_iso'] ?? '').toString());
    final dateSource = _normalizeDateSource(
      (json['date_source'] ?? '').toString(),
    );
    final rawNeedsReview = json['needs_review'] == true;
    final rawWarning = (json['warning'] ?? '').toString().trim();
    final needsReview = rawNeedsReview || dateSource == 'inferred';
    final warning =
        dateSource == 'inferred'
            ? _mergeWarnings(
              rawWarning,
              'Tanggal diinferensi dari konteks, mohon konfirmasi manual.',
            )
            : rawWarning;
    final confidence = _toInt(json['confidence']).clamp(0, 100);
    return ChatImportDraftItem(
      type: type,
      amount: amount,
      description: description,
      categoryHint: categoryHint,
      dateIso: dateIso,
      dateSource: dateSource,
      needsReview: needsReview,
      warning: warning,
      confidence: confidence,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _normalizeDateIso(String value) {
    final trimmed = value.trim();
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) {
      return '';
    }
    final y = parsed.year.toString().padLeft(4, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    final d = parsed.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _normalizeDateSource(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'explicit' ||
        normalized == 'inferred' ||
        normalized == 'unknown') {
      return normalized;
    }
    return 'unknown';
  }

  static String _mergeWarnings(String original, String extra) {
    final o = original.trim();
    final e = extra.trim();
    if (o.isEmpty) {
      return e;
    }
    if (o.toLowerCase().contains(e.toLowerCase())) {
      return o;
    }
    return '$o $e';
  }
}

class ChatImportDraft {
  const ChatImportDraft({
    required this.intent,
    required this.source,
    required this.transactions,
    required this.notesFound,
    required this.ignoredLines,
    required this.confidence,
    required this.isPartialDay,
    required this.missingOpeningBlock,
    required this.missingClosingTotal,
    required this.inferenceNotes,
  });

  final String intent;
  final String source;
  final List<ChatImportDraftItem> transactions;
  final List<String> notesFound;
  final List<String> ignoredLines;
  final int confidence;
  final bool isPartialDay;
  final bool missingOpeningBlock;
  final bool missingClosingTotal;
  final List<String> inferenceNotes;

  factory ChatImportDraft.fromJson(Map<String, dynamic> json) {
    final notesFound =
        (json['notes_found'] is List ? json['notes_found'] as List : const [])
            .map((v) => _normalizeWhitespace(v.toString()))
            .where((v) => v.isNotEmpty)
            .toList();
    final ignoredLines =
        (json['ignored_lines'] is List
                ? json['ignored_lines'] as List
                : const [])
            .map((v) => _normalizeWhitespace(v.toString()))
            .where((v) => v.isNotEmpty)
            .toList();

    final rawTransactions = json['transactions'];
    final transactions = <ChatImportDraftItem>[];
    if (rawTransactions is List) {
      for (final item in rawTransactions) {
        final map =
            item is Map<String, dynamic>
                ? item
                : item is Map
                ? Map<String, dynamic>.from(item)
                : <String, dynamic>{};
        final parsed = ChatImportDraftItem.fromJson(map);
        final sourceText = _normalizeWhitespace(parsed.description);
        if (sourceText.isEmpty) {
          continue;
        }

        if (_looksLikeNonTransactionLine(sourceText)) {
          _addUnique(ignoredLines, sourceText);
          continue;
        }

        final fromAmountField = _normalizeWhitespace(
          (map['amount'] ?? '').toString(),
        );
        final combinedText = '$sourceText $fromAmountField'.trim();
        final computedAmount = _deterministicAmount(
          existingAmount: parsed.amount,
          sourceText: combinedText,
        );
        if (computedAmount <= 0) {
          _addUnique(ignoredLines, sourceText);
          continue;
        }

        final cleanedDescription = _stripTrailingAmountTokens(sourceText);
        final hasMathExpression = _containsMathExpression(combinedText);
        final shouldApplyMathWarning =
            hasMathExpression &&
            computedAmount != parsed.amount &&
            computedAmount > 0;
        final warning = ChatImportDraftItem._mergeWarnings(
          parsed.warning,
          shouldApplyMathWarning
              ? 'Nominal gabungan dihitung otomatis oleh parser lokal.'
              : '',
        );
        final sanitized = parsed.copyWith(
          amount: computedAmount,
          description:
              cleanedDescription.length >= 2 ? cleanedDescription : sourceText,
          warning: warning,
          needsReview: parsed.needsReview || shouldApplyMathWarning,
        );
        if (sanitized.description.length < 2) {
          _addUnique(ignoredLines, sourceText);
          continue;
        }
        transactions.add(sanitized);
      }
    }

    final confidence = ChatImportDraftItem._toInt(
      json['confidence'],
    ).clamp(0, 100);
    final inferenceNotes =
        (json['inference_notes'] is List
                ? json['inference_notes'] as List
                : const [])
            .map((v) => v.toString().trim())
            .where((v) => v.isNotEmpty)
            .toList();

    return ChatImportDraft(
      intent: (json['intent'] ?? '').toString().trim(),
      source: (json['source'] ?? '').toString().trim(),
      transactions: transactions.take(30).toList(),
      notesFound: notesFound,
      ignoredLines: ignoredLines,
      confidence: confidence,
      isPartialDay: json['is_partial_day'] == true,
      missingOpeningBlock: json['missing_opening_block'] == true,
      missingClosingTotal: json['missing_closing_total'] == true,
      inferenceNotes: inferenceNotes,
    );
  }

  bool get isValid =>
      intent == 'import_transactions_draft' && transactions.isNotEmpty;

  static void _addUnique(List<String> target, String value) {
    final v = _normalizeWhitespace(value);
    if (v.isEmpty || target.contains(v)) {
      return;
    }
    target.add(v);
  }

  static String _normalizeWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _looksLikeNonTransactionLine(String description) {
    final lower = description.toLowerCase();
    const nonTxKeywords = <String>[
      'total',
      'jumlah',
      'uang bersih',
      'saldo',
      'grand total',
      'rekap',
      'subtotal',
    ];
    for (final keyword in nonTxKeywords) {
      if (lower.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static int _deterministicAmount({
    required int existingAmount,
    required String sourceText,
  }) {
    final values = _extractAmountCandidates(sourceText);
    if (values.isEmpty) {
      return existingAmount > 0 ? existingAmount : 0;
    }

    final hasMath = _containsMathExpression(sourceText);
    if (hasMath) {
      final sum = values.fold<int>(0, (acc, v) => acc + v);
      if (sum > 0) {
        return sum;
      }
    }

    final large = values.where((v) => v >= 1000).toList();
    final fallback = (large.isNotEmpty ? large.last : values.last);
    if (existingAmount > 0 && existingAmount >= fallback) {
      return existingAmount;
    }
    return fallback;
  }

  static bool _containsMathExpression(String sourceText) {
    return RegExp(r'\d[\d\.\,\s]*\+\s*\d').hasMatch(sourceText);
  }

  static List<int> _extractAmountCandidates(String sourceText) {
    final matches = RegExp(
      r'\d[\d\.\,\s]{0,}',
    ).allMatches(sourceText).map((m) => m.group(0) ?? '');
    final values = <int>[];
    for (final raw in matches) {
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) {
        continue;
      }
      final parsed = int.tryParse(digits);
      if (parsed != null && parsed > 0) {
        values.add(parsed);
      }
    }
    return values;
  }

  static String _stripTrailingAmountTokens(String description) {
    final cleaned = description.replaceFirst(
      RegExp(r'[\s\-:]*\d[\d\.\,\s]*(?:\+\s*\d[\d\.\,\s]*)*$'),
      '',
    );
    return _normalizeWhitespace(cleaned);
  }
}
