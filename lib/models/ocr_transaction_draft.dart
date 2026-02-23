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
    );
  }
}

class OcrBatchDraft {
  const OcrBatchDraft({
    required this.isTransaction,
    required this.reason,
    required this.transactions,
  });

  final bool isTransaction;
  final String reason;
  final List<OcrTransactionDraft> transactions;

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

    return OcrBatchDraft(
      isTransaction: isTransaction,
      reason: (json['reason'] ?? '').toString().trim(),
      transactions: transactions,
    );
  }
}
