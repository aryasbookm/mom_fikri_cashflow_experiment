class OcrTransactionDraft {
  const OcrTransactionDraft({
    required this.isTransaction,
    required this.reason,
    required this.type,
    required this.amount,
    required this.description,
    required this.categoryHint,
    required this.dateIso,
    required this.confidence,
    required this.rawText,
    required this.needsReview,
    required this.warning,
  });

  final bool isTransaction;
  final String reason;
  final String type;
  final int amount;
  final String description;
  final String categoryHint;
  final String dateIso;
  final int confidence;
  final String rawText;
  final bool needsReview;
  final String warning;

  factory OcrTransactionDraft.fromJson(Map<String, dynamic> json) {
    final typeRaw = (json['type'] ?? '').toString().toUpperCase().trim();
    final type = typeRaw == 'OUT' ? 'OUT' : 'IN';

    final amountValue = json['amount'];
    final amount =
        amountValue is num
            ? amountValue.toInt()
            : int.tryParse((amountValue ?? '').toString()) ?? 0;

    final confidenceValue = json['confidence'];
    final confidence =
        confidenceValue is num
            ? confidenceValue.toInt().clamp(0, 100)
            : int.tryParse((confidenceValue ?? '').toString())?.clamp(0, 100) ??
                0;

    final dateIso = (json['date_iso'] ?? '').toString().trim();
    final isTransactionValue = json['is_transaction'];
    final isTransaction =
        isTransactionValue is bool
            ? isTransactionValue
            : (isTransactionValue ?? '').toString().toLowerCase().trim() ==
                'true';
    final needsReviewValue = json['needs_review'];
    final needsReview =
        needsReviewValue is bool
            ? needsReviewValue
            : (needsReviewValue ?? '').toString().toLowerCase().trim() ==
                'true';

    return OcrTransactionDraft(
      isTransaction: isTransaction,
      reason: (json['reason'] ?? '').toString().trim(),
      type: type,
      amount: amount < 0 ? 0 : amount,
      description: (json['description'] ?? '').toString().trim(),
      categoryHint: (json['category_hint'] ?? '').toString().trim(),
      dateIso: dateIso,
      confidence: confidence,
      rawText: (json['raw_text'] ?? '').toString().trim(),
      needsReview: needsReview,
      warning: (json['warning'] ?? '').toString().trim(),
    );
  }
}

class OcrBatchDraft {
  const OcrBatchDraft({
    required this.isTransaction,
    required this.reason,
    required this.transactions,
    required this.detectedDate,
    required this.notesFound,
    required this.ignoredLines,
  });

  final bool isTransaction;
  final String reason;
  final List<OcrTransactionDraft> transactions;
  final String detectedDate;
  final List<String> notesFound;
  final List<String> ignoredLines;

  int get reviewCount => transactions.where((t) => t.needsReview).length;

  factory OcrBatchDraft.fromJson(Map<String, dynamic> json) {
    final isTransactionValue = json['is_transaction'];
    final isTransaction =
        isTransactionValue is bool
            ? isTransactionValue
            : (isTransactionValue ?? '').toString().toLowerCase().trim() ==
                'true';

    final itemsRaw = json['transactions'];
    final itemsList = itemsRaw is List ? itemsRaw : const [];

    final transactions = <OcrTransactionDraft>[];
    for (final item in itemsList) {
      if (item is Map<String, dynamic>) {
        transactions.add(OcrTransactionDraft.fromJson(item));
      } else if (item is Map) {
        transactions.add(
          OcrTransactionDraft.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    }

    final summaryRaw =
        json['summary'] is Map<String, dynamic>
            ? json['summary'] as Map<String, dynamic>
            : json['summary'] is Map
            ? Map<String, dynamic>.from(json['summary'] as Map)
            : <String, dynamic>{};

    final notes = <String>[];
    final notesRaw = summaryRaw['notes_found'];
    if (notesRaw is List) {
      for (final note in notesRaw) {
        if (note is String && note.trim().isNotEmpty) {
          notes.add(note.trim());
          continue;
        }
        if (note is Map) {
          final map =
              note is Map<String, dynamic>
                  ? note
                  : Map<String, dynamic>.from(note);
          final label = (map['label'] ?? '').toString().trim();
          final value = (map['value'] ?? '').toString().trim();
          if (label.isNotEmpty || value.isNotEmpty) {
            notes.add(
              [
                if (label.isNotEmpty) label,
                if (value.isNotEmpty) value,
              ].join(': '),
            );
          }
        }
      }
    }

    final ignored = <String>[];
    final ignoredRaw = json['ignored_lines'];
    if (ignoredRaw is List) {
      for (final line in ignoredRaw) {
        final text = (line ?? '').toString().trim();
        if (text.isNotEmpty) {
          ignored.add(text);
        }
      }
    }

    return OcrBatchDraft(
      isTransaction: isTransaction,
      reason: (json['reason'] ?? '').toString().trim(),
      transactions: transactions,
      detectedDate: (summaryRaw['date_detected'] ?? '').toString().trim(),
      notesFound: notes,
      ignoredLines: ignored,
    );
  }
}
