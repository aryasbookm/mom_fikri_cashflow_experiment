import '../models/ocr_transaction_draft.dart';
import 'ai_provider_router.dart';

class AiOcrService {
  AiOcrService({AiProviderRouter? router})
    : _router = router ?? AiProviderRouter();

  final AiProviderRouter _router;

  Future<OcrBatchDraft> extractDraftFromImageBytes({
    required List<int> imageBytes,
    required String mimeType,
    String? providerOrderOverride,
    String? geminiOcrModelChainOverride,
    void Function(
      String providerId,
      String status,
      String? detail, [
      String? stage,
    ])?
    onProviderEvent,
  }) async {
    return _router.extractDraftFromImageBytes(
      imageBytes: imageBytes,
      mimeType: mimeType,
      providerOrderOverride: providerOrderOverride,
      geminiOcrModelChainOverride: geminiOcrModelChainOverride,
      onProviderEvent: onProviderEvent,
    );
  }
}
