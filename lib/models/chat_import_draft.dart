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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'amount': amount,
      'description': description,
      'category_hint': categoryHint,
      'date_iso': dateIso,
      'date_source': dateSource,
      'needs_review': needsReview,
      'warning': warning,
      'confidence': confidence,
    };
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
    required this.importHash,
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
  final String importHash;
  final List<ChatImportDraftItem> transactions;
  final List<String> notesFound;
  final List<String> ignoredLines;
  final int confidence;
  final bool isPartialDay;
  final bool missingOpeningBlock;
  final bool missingClosingTotal;
  final List<String> inferenceNotes;

  ChatImportDraft copyWith({
    String? intent,
    String? source,
    String? importHash,
    List<ChatImportDraftItem>? transactions,
    List<String>? notesFound,
    List<String>? ignoredLines,
    int? confidence,
    bool? isPartialDay,
    bool? missingOpeningBlock,
    bool? missingClosingTotal,
    List<String>? inferenceNotes,
  }) {
    return ChatImportDraft(
      intent: intent ?? this.intent,
      source: source ?? this.source,
      importHash: importHash ?? this.importHash,
      transactions: transactions ?? this.transactions,
      notesFound: notesFound ?? this.notesFound,
      ignoredLines: ignoredLines ?? this.ignoredLines,
      confidence: confidence ?? this.confidence,
      isPartialDay: isPartialDay ?? this.isPartialDay,
      missingOpeningBlock: missingOpeningBlock ?? this.missingOpeningBlock,
      missingClosingTotal: missingClosingTotal ?? this.missingClosingTotal,
      inferenceNotes: inferenceNotes ?? this.inferenceNotes,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'intent': intent,
      'source': source,
      'import_hash': importHash,
      'transactions': transactions
          .map((item) => item.toJson())
          .toList(growable: false),
      'notes_found': notesFound,
      'ignored_lines': ignoredLines,
      'confidence': confidence,
      'is_partial_day': isPartialDay,
      'missing_opening_block': missingOpeningBlock,
      'missing_closing_total': missingClosingTotal,
      'inference_notes': inferenceNotes,
    };
  }

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
    final normalizedTransactions = _applyDeterministicDateInference(
      transactions: transactions,
      inferenceNotes: inferenceNotes,
    );

    return ChatImportDraft(
      intent: (json['intent'] ?? '').toString().trim(),
      source: (json['source'] ?? '').toString().trim(),
      importHash: (json['import_hash'] ?? '').toString().trim(),
      transactions: normalizedTransactions.take(30).toList(),
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
    final normalized = _normalizeSuspiciousAmountText(sourceText);
    final values = _extractAmountCandidates(normalized);
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
      final parsed = _parseDigitsWithRepeatGuard(digits);
      if (parsed != null && parsed > 0) {
        values.add(parsed);
      }
    }
    return values;
  }

  static int? _parseDigitsWithRepeatGuard(String digits) {
    final parsed = int.tryParse(digits);
    if (parsed == null || parsed <= 0) {
      return null;
    }
    final half = _tryHalfRepeatDigits(digits);
    if (half != null) {
      return half;
    }
    return parsed;
  }

  static int? _tryHalfRepeatDigits(String digits) {
    if (digits.length < 8 || digits.length.isOdd) {
      return null;
    }
    final mid = digits.length ~/ 2;
    final left = digits.substring(0, mid);
    final right = digits.substring(mid);
    if (left != right) {
      return null;
    }
    return int.tryParse(left);
  }

  static String _normalizeSuspiciousAmountText(String sourceText) {
    var text = sourceText;
    text = text.replaceAllMapped(
      RegExp(r'(\d{1,3}(?:[.,]\d{3})+)\s*\1'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(\d{4,})\s*\1\b'),
      (m) => m.group(1) ?? '',
    );
    return text;
  }

  static List<ChatImportDraftItem> _applyDeterministicDateInference({
    required List<ChatImportDraftItem> transactions,
    required List<String> inferenceNotes,
  }) {
    if (transactions.isEmpty) {
      return transactions;
    }
    final explicitIndices = <int>[];
    for (var i = 0; i < transactions.length; i++) {
      final item = transactions[i];
      if (item.dateIso.trim().isNotEmpty && item.dateSource == 'explicit') {
        explicitIndices.add(i);
      }
    }

    final result = List<ChatImportDraftItem>.from(transactions);
    if (explicitIndices.isEmpty) {
      final now = DateTime.now();
      final todayIso =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      for (var i = 0; i < result.length; i++) {
        if (result[i].dateIso.trim().isNotEmpty) {
          continue;
        }
        result[i] = _applyInferredDate(
          item: result[i],
          dateIso: todayIso,
          extraWarning:
              'Tanggal tidak ditemukan pada input, sistem memakai tanggal hari ini.',
        );
      }
      _addUnique(
        inferenceNotes,
        'Sebagian tanggal tidak ditemukan; fallback ke tanggal hari ini.',
      );
      return result;
    }

    final firstExplicit = explicitIndices.first;
    final firstDate = DateTime.tryParse(result[firstExplicit].dateIso);
    if (firstDate != null) {
      final previous = firstDate.subtract(const Duration(days: 1));
      final previousIso =
          '${previous.year.toString().padLeft(4, '0')}-${previous.month.toString().padLeft(2, '0')}-${previous.day.toString().padLeft(2, '0')}';
      for (var i = 0; i < firstExplicit; i++) {
        if (result[i].dateIso.trim().isNotEmpty) {
          continue;
        }
        result[i] = _applyInferredDate(
          item: result[i],
          dateIso: previousIso,
          extraWarning:
              'Tanggal diasumsikan hari sebelumnya dari blok tanggal eksplisit berikutnya.',
        );
      }
    }

    String? lastKnownIso;
    for (var i = 0; i < result.length; i++) {
      final item = result[i];
      if (item.dateIso.trim().isNotEmpty) {
        lastKnownIso = item.dateIso;
        continue;
      }
      if (lastKnownIso == null) {
        continue;
      }
      result[i] = _applyInferredDate(
        item: item,
        dateIso: lastKnownIso,
        extraWarning:
            'Tanggal melanjutkan blok tanggal eksplisit terakhir pada input.',
      );
    }
    return result;
  }

  static ChatImportDraftItem _applyInferredDate({
    required ChatImportDraftItem item,
    required String dateIso,
    required String extraWarning,
  }) {
    return item.copyWith(
      dateIso: dateIso,
      dateSource: 'inferred',
      needsReview: true,
      warning: ChatImportDraftItem._mergeWarnings(item.warning, extraWarning),
    );
  }

  static String _stripTrailingAmountTokens(String description) {
    final cleaned = description.replaceFirst(
      RegExp(r'[\s\-:]*\d[\d\.\,\s]*(?:\+\s*\d[\d\.\,\s]*)*$'),
      '',
    );
    return _normalizeWhitespace(cleaned);
  }
}
