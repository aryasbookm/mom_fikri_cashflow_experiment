import '../../models/ocr_transaction_draft.dart';

typedef OcrProviderStageCallback =
    void Function(String stage, String status, String? detail);

abstract class AiVisionProvider {
  String get providerId;

  Duration? get requestTimeout => null;

  Future<OcrBatchDraft> extractDraftFromImageBytes({
    required List<int> imageBytes,
    required String mimeType,
    OcrProviderStageCallback? onProviderEvent,
  });
}

class AiProviderTemporaryException implements Exception {
  const AiProviderTemporaryException(this.message);

  final String message;

  @override
  String toString() => message;
}
