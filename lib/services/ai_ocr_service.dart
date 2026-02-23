import '../models/ocr_transaction_draft.dart';
import 'ai_provider_router.dart';

class AiOcrService {
  AiOcrService({AiProviderRouter? router}) : _router = router ?? AiProviderRouter();

  final AiProviderRouter _router;

  Future<OcrBatchDraft> extractDraftFromImageBytes({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    return _router.extractDraftFromImageBytes(
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
  }
}
