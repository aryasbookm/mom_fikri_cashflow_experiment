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
        if (_isProviderConfigured('gemini')) {
          for (final model in _geminiOcrModelsFromEnvironment()) {
            providers.add(GeminiVisionProvider(model: model));
          }
        }
      } else if (id == 'groq') {
        if (_isProviderConfigured('groq')) {
          providers.add(GroqVisionProvider());
        }
      }
      // next providers can be registered here (example: claude, etc.)
    }

    if (providers.isEmpty) {
      if (_isProviderConfigured('gemini')) {
        providers.add(
          GeminiVisionProvider(
            model: _geminiOcrModelsFromEnvironment().firstOrNull,
          ),
        );
      } else if (_isProviderConfigured('groq')) {
        providers.add(GroqVisionProvider());
      }
    }
    return providers;
  }

  static List<String> _geminiOcrModelsFromEnvironment() {
    final chain = String.fromEnvironment(
      'GEMINI_OCR_MODEL_CHAIN',
      defaultValue:
          'gemini-2.5-flash-lite,gemini-3-flash-preview,gemini-2.5-flash,gemini-3.1-pro-preview',
    );
    final models =
        chain
            .split(',')
            .map((entry) => entry.trim())
            .where((entry) => entry.isNotEmpty)
            .toList();
    if (models.isEmpty) {
      return const ['gemini-2.5-flash'];
    }
    final deduped = <String>[];
    for (final model in models) {
      if (!deduped.contains(model)) {
        deduped.add(model);
      }
    }
    return deduped;
  }

  static bool _isProviderConfigured(String providerId) {
    switch (providerId) {
      case 'gemini':
        return const String.fromEnvironment('GEMINI_API_KEY').trim().isNotEmpty;
      case 'groq':
        return const String.fromEnvironment('GROQ_API_KEY').trim().isNotEmpty;
      default:
        return false;
    }
  }
}

extension on List<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
