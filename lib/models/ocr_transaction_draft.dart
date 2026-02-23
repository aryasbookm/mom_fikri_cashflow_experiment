class OcrTransactionDraft {
  const OcrTransactionDraft({
    required this.type,
    required this.amount,
    required this.description,
    required this.categoryHint,
    required this.dateIso,
    required this.confidence,
    required this.rawText,
  });

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

    return OcrTransactionDraft(
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
