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
        if (parsed.amount <= 0 || parsed.description.length < 2) {
          continue;
        }
        transactions.add(parsed);
      }
    }

    final notesFound =
        (json['notes_found'] is List ? json['notes_found'] as List : const [])
            .map((v) => v.toString().trim())
            .where((v) => v.isNotEmpty)
            .toList();
    final ignoredLines =
        (json['ignored_lines'] is List
                ? json['ignored_lines'] as List
                : const [])
            .map((v) => v.toString().trim())
            .where((v) => v.isNotEmpty)
            .toList();

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
}
