import 'dart:async';

import '../models/ocr_transaction_draft.dart';
import 'ai_insight_service.dart';
import 'ai_providers/ai_vision_provider.dart';
import 'ai_providers/gemini_vision_provider.dart';
import 'ai_providers/groq_vision_provider.dart';

class AiProviderRouter {
  AiProviderRouter({List<AiVisionProvider>? providers})
    : _providers = providers;

  final List<AiVisionProvider>? _providers;
  static final Map<String, _ModelFailureState> _modelFailureStates = {};
  static const int _jsonInvalidFailureThreshold = 2;
  static const Duration _jsonInvalidBackoffDuration = Duration(minutes: 15);
  static const Duration _defaultProviderTimeout = Duration(seconds: 10);

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
    final providers =
        _providers ??
        _providersFromEnvironment(
          orderOverride: providerOrderOverride,
          geminiChainOverride: geminiOcrModelChainOverride,
        );
    if (providers.isEmpty) {
      throw Exception('Provider AI belum dikonfigurasi.');
    }

    Object? lastFallbackError;

    for (var i = 0; i < providers.length; i++) {
      final provider = providers[i];
      final hasNext = i < providers.length - 1;
      final now = DateTime.now();
      final failureState = _modelFailureStates[provider.providerId];
      if (failureState != null &&
          failureState.skipUntil != null &&
          failureState.skipUntil!.isAfter(now)) {
        onProviderEvent?.call(
          provider.providerId,
          'skipped',
          'Model dilewati sementara karena gagal format JSON berulang.',
        );
        continue;
      }
      onProviderEvent?.call(provider.providerId, 'try', null);
      try {
        final timeout = provider.requestTimeout ?? _defaultProviderTimeout;
        final result = await provider
            .extractDraftFromImageBytes(
              imageBytes: imageBytes,
              mimeType: mimeType,
              onProviderEvent: (stage, status, detail) {
                onProviderEvent?.call(
                  provider.providerId,
                  status,
                  detail,
                  stage,
                );
              },
            )
            .timeout(timeout);
        onProviderEvent?.call(provider.providerId, 'ok', null);
        _modelFailureStates.remove(provider.providerId);
        return result;
      } on TimeoutException {
        const error = AiProviderTemporaryException(
          'Permintaan OCR AI timeout. Coba lagi.',
        );
        onProviderEvent?.call(
          provider.providerId,
          'temporary',
          error.toString(),
        );
        lastFallbackError = error;
        if (!hasNext) {
          throw error;
        }
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
        _recordJsonInvalidFailureIfNeeded(
          providerId: provider.providerId,
          detail: error.toString(),
        );
        lastFallbackError = error;
        if (!hasNext) {
          rethrow;
        }
      } catch (error) {
        onProviderEvent?.call(provider.providerId, 'error', error.toString());
        // Keep trying next provider for OCR robustness (format/provider mismatch, etc).
        _recordJsonInvalidFailureIfNeeded(
          providerId: provider.providerId,
          detail: error.toString(),
        );
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

  static void _recordJsonInvalidFailureIfNeeded({
    required String providerId,
    required String detail,
  }) {
    final normalized = detail.toLowerCase();
    final isJsonInvalid = normalized.contains('format json ocr ai tidak valid');
    if (!isJsonInvalid) {
      return;
    }
    final current =
        _modelFailureStates[providerId] ??
        _ModelFailureState(providerId: providerId);
    final nextFailures = current.jsonInvalidFailures + 1;
    DateTime? skipUntil = current.skipUntil;
    if (nextFailures >= _jsonInvalidFailureThreshold) {
      skipUntil = DateTime.now().add(_jsonInvalidBackoffDuration);
    }
    _modelFailureStates[providerId] = current.copyWith(
      jsonInvalidFailures: nextFailures,
      skipUntil: skipUntil,
    );
  }

  static List<AiVisionProvider> _providersFromEnvironment({
    String? orderOverride,
    String? geminiChainOverride,
  }) {
    final order =
        (orderOverride ?? '').trim().isNotEmpty
            ? orderOverride!.trim()
            : String.fromEnvironment(
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
          for (final model in _geminiOcrModelsFromEnvironment(
            chainOverride: geminiChainOverride,
          )) {
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
            model:
                _geminiOcrModelsFromEnvironment(
                  chainOverride: geminiChainOverride,
                ).firstOrNull,
          ),
        );
      } else if (_isProviderConfigured('groq')) {
        providers.add(GroqVisionProvider());
      }
    }
    return providers;
  }

  static List<String> _geminiOcrModelsFromEnvironment({String? chainOverride}) {
    final chain =
        (chainOverride ?? '').trim().isNotEmpty
            ? chainOverride!.trim()
            : String.fromEnvironment(
              'GEMINI_OCR_MODEL_CHAIN',
              defaultValue:
                  'gemini-3.1-pro-preview,gemini-3-flash-preview,gemini-2.5-flash,gemini-2.5-flash-lite',
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

class _ModelFailureState {
  const _ModelFailureState({
    required this.providerId,
    this.jsonInvalidFailures = 0,
    this.skipUntil,
  });

  final String providerId;
  final int jsonInvalidFailures;
  final DateTime? skipUntil;

  _ModelFailureState copyWith({
    String? providerId,
    int? jsonInvalidFailures,
    DateTime? skipUntil,
  }) {
    return _ModelFailureState(
      providerId: providerId ?? this.providerId,
      jsonInvalidFailures: jsonInvalidFailures ?? this.jsonInvalidFailures,
      skipUntil: skipUntil ?? this.skipUntil,
    );
  }
}
