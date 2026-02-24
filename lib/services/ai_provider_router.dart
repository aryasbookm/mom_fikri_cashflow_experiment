import '../models/ocr_transaction_draft.dart';
import 'ai_insight_service.dart';
import 'ai_providers/ai_vision_provider.dart';
import 'ai_providers/gemini_vision_provider.dart';
import 'ai_providers/groq_vision_provider.dart';

class AiProviderRouter {
  AiProviderRouter({List<AiVisionProvider>? providers})
    : _providers = providers ?? _providersFromEnvironment();

  final List<AiVisionProvider> _providers;

  Future<OcrBatchDraft> extractDraftFromImageBytes({
    required List<int> imageBytes,
    required String mimeType,
    void Function(String providerId, String status, String? detail)?
    onProviderEvent,
  }) async {
    if (_providers.isEmpty) {
      throw Exception('Provider AI belum dikonfigurasi.');
    }

    Object? lastFallbackError;

    for (var i = 0; i < _providers.length; i++) {
      final provider = _providers[i];
      final hasNext = i < _providers.length - 1;
      onProviderEvent?.call(provider.providerId, 'try', null);
      try {
        final result = await provider.extractDraftFromImageBytes(
          imageBytes: imageBytes,
          mimeType: mimeType,
        );
        onProviderEvent?.call(provider.providerId, 'ok', null);
        return result;
      } on AiRateLimitException catch (error) {
        onProviderEvent?.call(
          provider.providerId,
          'rate_limit',
          error.toString(),
        );
        lastFallbackError = error;
        if (!hasNext) {
          rethrow;
        }
      } on AiProviderTemporaryException catch (error) {
        onProviderEvent?.call(
          provider.providerId,
          'temporary',
          error.toString(),
        );
        lastFallbackError = error;
        if (!hasNext) {
          rethrow;
        }
      } catch (error) {
        onProviderEvent?.call(provider.providerId, 'error', error.toString());
        // Keep trying next provider for OCR robustness (format/provider mismatch, etc).
        lastFallbackError = error;
        if (!hasNext) {
          rethrow;
        }
      }
    }

    if (lastFallbackError != null) {
      throw lastFallbackError;
    }
    throw Exception('Gagal memproses OCR AI.');
  }

  static List<AiVisionProvider> _providersFromEnvironment() {
    final order = String.fromEnvironment(
      'AI_PROVIDER_ORDER',
      defaultValue: 'gemini,groq',
    );
    final requested =
        order
            .split(',')
            .map((entry) => entry.trim().toLowerCase())
            .where((entry) => entry.isNotEmpty)
            .toList();

    final providers = <AiVisionProvider>[];
    for (final id in requested) {
      if (id == 'gemini') {
        providers.add(GeminiVisionProvider());
      } else if (id == 'groq') {
        providers.add(GroqVisionProvider());
      }
      // next providers can be registered here (example: claude, etc.)
    }

    if (providers.isEmpty) {
      providers.add(GeminiVisionProvider());
    }
    return providers;
  }
}
