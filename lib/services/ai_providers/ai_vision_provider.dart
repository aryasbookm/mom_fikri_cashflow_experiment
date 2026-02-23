import '../../models/ocr_transaction_draft.dart';

abstract class AiVisionProvider {
  String get providerId;

  Future<OcrBatchDraft> extractDraftFromImageBytes({
    required List<int> imageBytes,
    required String mimeType,
  });
}

class AiProviderTemporaryException implements Exception {
  const AiProviderTemporaryException(this.message);

  final String message;

  @override
  String toString() => message;
}

