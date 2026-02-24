import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_providers/ai_vision_provider.dart';

enum AiQuotaType { rpm, tpm, rpd, unknown }

const bool _aiDebugLog = bool.fromEnvironment(
  'AI_DEBUG_LOG',
  defaultValue: false,
);

class AiRateLimitException implements Exception {
  const AiRateLimitException({
    required this.retryAfterSeconds,
    required this.quotaType,
    required this.isDailyLimit,
    this.message,
  });

  final int retryAfterSeconds;
  final AiQuotaType quotaType;
  final bool isDailyLimit;
  final String? message;

  @override
  String toString() {
    if (message != null && message!.trim().isNotEmpty) {
      return message!;
    }
    return _friendlyQuotaMessage(
      quotaType: quotaType,
      retryAfterSeconds: retryAfterSeconds,
      isDailyLimit: isDailyLimit,
    );
  }
}

AiRateLimitException buildAiRateLimitExceptionFromResponse(
  http.Response response,
) {
  const fallbackRetryAfter = 60;
  final retryAfterHeader = _parseRetryAfterSecondsFromHeader(
    response.headers['retry-after'],
  );

  AiQuotaType quotaType = AiQuotaType.unknown;
  var isDailyLimit = false;
  var retryAfterSeconds = retryAfterHeader;
  String? message;

  try {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final error = body['error'] as Map<String, dynamic>?;
    final details = error?['details'];
    if (details is List) {
      for (final detail in details) {
        final map =
            detail is Map<String, dynamic>
                ? detail
                : detail is Map
                ? Map<String, dynamic>.from(detail)
                : null;
        if (map == null) {
          continue;
        }
        final type = (map['@type'] ?? '').toString();
        if (type.contains('google.rpc.QuotaFailure')) {
          final violations = map['violations'];
          if (violations is List) {
            for (final violation in violations) {
              final vMap =
                  violation is Map<String, dynamic>
                      ? violation
                      : violation is Map
                      ? Map<String, dynamic>.from(violation)
                      : null;
              if (vMap == null) {
                continue;
              }
              final metric =
                  '${vMap['quotaMetric'] ?? ''} ${vMap['quotaId'] ?? ''} ${vMap['subject'] ?? ''}'
                      .toLowerCase();
              if (metric.contains('perday') ||
                  metric.contains('daily') ||
                  metric.contains('rpd')) {
                quotaType = AiQuotaType.rpd;
                isDailyLimit = true;
              } else if (metric.contains('token') ||
                  metric.contains('input_token') ||
                  metric.contains('output_token') ||
                  metric.contains('tpm')) {
                quotaType = AiQuotaType.tpm;
              } else if (metric.contains('request') ||
                  metric.contains('rpm') ||
                  metric.contains('perminute')) {
                quotaType = AiQuotaType.rpm;
              }
            }
          }
        } else if (type.contains('google.rpc.RetryInfo')) {
          final retryDelay = (map['retryDelay'] ?? '').toString();
          final parsedRetry = _parseRetryDelaySeconds(retryDelay);
          if (parsedRetry != null) {
            retryAfterSeconds = parsedRetry;
          }
        }
      }
    }

    final status = (error?['status'] ?? '').toString().toUpperCase();
    if (status == 'RESOURCE_EXHAUSTED' && quotaType == AiQuotaType.unknown) {
      quotaType = AiQuotaType.rpm;
    }
    final rawMessage = (error?['message'] ?? '').toString().trim();
    if (rawMessage.isNotEmpty) {
      final lower = rawMessage.toLowerCase();
      if (lower.contains('per day') || lower.contains('daily')) {
        quotaType = AiQuotaType.rpd;
        isDailyLimit = true;
      } else if (lower.contains('token')) {
        quotaType = AiQuotaType.tpm;
      } else if (lower.contains('per minute') ||
          lower.contains('rate limit') ||
          lower.contains('too many requests')) {
        quotaType = AiQuotaType.rpm;
      }
      if (_aiDebugLog) {
        developer.log('Gemini 429 raw message: $rawMessage');
      }
    }
  } catch (_) {
    // keep fallback mapping
  }

  if (retryAfterSeconds <= 0) {
    retryAfterSeconds = fallbackRetryAfter;
  }
  if (isDailyLimit) {
    retryAfterSeconds = 0;
    message ??= 'Limit AI harian sudah habis. Silakan coba lagi besok.';
  }

  return AiRateLimitException(
    retryAfterSeconds: retryAfterSeconds,
    quotaType: quotaType,
    isDailyLimit: isDailyLimit,
    message: message,
  );
}

String _friendlyQuotaMessage({
  required AiQuotaType quotaType,
  required int retryAfterSeconds,
  required bool isDailyLimit,
}) {
  if (isDailyLimit || quotaType == AiQuotaType.rpd) {
    return 'Batas AI hari ini habis. Coba lagi besok.';
  }
  switch (quotaType) {
    case AiQuotaType.rpm:
      return 'Terlalu sering meminta AI. Coba lagi dalam $retryAfterSeconds detik.';
    case AiQuotaType.tpm:
      return 'Data scan terlalu berat untuk saat ini. Coba lagi dalam $retryAfterSeconds detik.';
    case AiQuotaType.rpd:
      return 'Batas AI hari ini habis. Coba lagi besok.';
    case AiQuotaType.unknown:
      return 'AI sedang sibuk. Coba lagi dalam $retryAfterSeconds detik.';
  }
}

class AiInsightResult {
  const AiInsightResult({
    required this.text,
    required this.fromCache,
    required this.providerId,
    required this.suggestedCooldownSeconds,
  });

  final String text;
  final bool fromCache;
  final String providerId;
  final int suggestedCooldownSeconds;
}

class _InsightProviderResponse {
  const _InsightProviderResponse({
    required this.providerId,
    required this.body,
  });

  final String providerId;
  final Map<String, dynamic> body;
}

class AiInsightService {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _groqApiKey = String.fromEnvironment('GROQ_API_KEY');
  static const String _model = String.fromEnvironment(
    'GEMINI_INSIGHT_MODEL',
    defaultValue: 'gemma-3-12b',
  );
  static const String _groqModel = String.fromEnvironment(
    'GROQ_CHAT_MODEL',
    defaultValue: 'llama-3.1-8b-instant',
  );
  static const bool _debugLog = _aiDebugLog;
  static const int _maxOutputTokens = 900;
  static const int _maxProviderRetries = 2;
  static const Duration _cacheTtl = Duration(minutes: 45);
  static const String _cacheKeyText = 'ai_insight_cache_text_v1';
  static const String _cacheKeyHash = 'ai_insight_cache_hash_v1';
  static const String _cacheKeyEpoch = 'ai_insight_cache_epoch_v1';

  Future<String> generateOwnerInsight({
    required int income30,
    required int expense30,
    required int net30,
    required List<Map<String, dynamic>> topProducts,
    required List<Map<String, dynamic>> slowMovingProducts,
  }) async {
    final result = await generateOwnerInsightResult(
      income30: income30,
      expense30: expense30,
      net30: net30,
      topProducts: topProducts,
      slowMovingProducts: slowMovingProducts,
    );
    return result.text;
  }

  Future<AiInsightResult> generateOwnerInsightResult({
    required int income30,
    required int expense30,
    required int net30,
    required List<Map<String, dynamic>> topProducts,
    required List<Map<String, dynamic>> slowMovingProducts,
  }) async {
    final normalizedTop = _normalizeProductRows(topProducts);
    final normalizedSlow = _normalizeProductRows(slowMovingProducts);

    final fingerprint = _buildInsightFingerprint(
      income30: income30,
      expense30: expense30,
      net30: net30,
      topProducts: normalizedTop,
      slowMovingProducts: normalizedSlow,
    );

    final cached = await _tryGetCachedInsight(fingerprint);
    if (cached != null) {
      if (_debugLog) {
        developer.log('Using cached AI insight.', name: 'AI_DEBUG');
      }
      return AiInsightResult(
        text: cached,
        fromCache: true,
        providerId: 'cache',
        suggestedCooldownSeconds: 1,
      );
    }

    final topText =
        normalizedTop.isEmpty
            ? '- Tidak ada data produk terlaris.'
            : normalizedTop
                .map((item) {
                  final name = item['name'] ?? '-';
                  final qty = item['total_qty'] ?? 0;
                  return '- $name: terjual $qty pcs';
                })
                .join('\n');

    final slowText =
        normalizedSlow.isEmpty
            ? '- Tidak ada data produk kurang laris.'
            : normalizedSlow
                .map((item) {
                  final name = item['name'] ?? '-';
                  final qty = item['total_qty'] ?? 0;
                  final stock = item['stock'] ?? 0;
                  return '- $name: terjual $qty pcs, stok saat ini $stock pcs';
                })
                .join('\n');

    final prompt = _buildInsightPrompt(
      income30: income30,
      expense30: expense30,
      net30: net30,
      topText: topText,
      slowText: slowText,
    );

    final firstResponse = await _requestInsightWithFallback(
      prompt,
      temperature: 0.25,
    );
    final firstText = _extractJoinedText(firstResponse.body);
    final firstStructured = _tryParseInsightJson(firstText);
    final firstReasons = _extractFinishReasons(firstResponse.body);
    final needsRetry =
        firstStructured == null || firstReasons.contains('MAX_TOKENS');

    if (!needsRetry) {
      final rendered = _renderStructuredInsight(firstStructured);
      await _saveCachedInsight(fingerprint: fingerprint, insight: rendered);
      return AiInsightResult(
        text: rendered,
        fromCache: false,
        providerId: firstResponse.providerId,
        suggestedCooldownSeconds: _cooldownAfterSuccess(
          firstResponse.providerId,
        ),
      );
    }

    if (_debugLog) {
      developer.log(
        'AI response incomplete/generic, running one retry with stricter prompt.',
        name: 'AI_DEBUG',
      );
    }

    final retryPrompt = _buildStrictRetryPrompt(
      income30: income30,
      expense30: expense30,
      net30: net30,
      topText: topText,
      slowText: slowText,
    );

    final retryResponse = await _requestInsightWithFallback(
      retryPrompt,
      temperature: 0.2,
    );
    final retryText = _extractJoinedText(retryResponse.body);
    final retryStructured = _tryParseInsightJson(retryText);

    if (retryStructured == null) {
      if (_debugLog) {
        developer.log(
          'Retry response still incomplete, using local deterministic fallback.',
          name: 'AI_DEBUG',
        );
      }
      final fallback = _buildLocalFallbackInsight(
        income30: income30,
        expense30: expense30,
        net30: net30,
        topProducts: normalizedTop,
        slowMovingProducts: normalizedSlow,
      );
      await _saveCachedInsight(fingerprint: fingerprint, insight: fallback);
      return AiInsightResult(
        text: fallback,
        fromCache: false,
        providerId: 'local-fallback',
        suggestedCooldownSeconds: 2,
      );
    }

    final rendered = _renderStructuredInsight(retryStructured);
    await _saveCachedInsight(fingerprint: fingerprint, insight: rendered);
    return AiInsightResult(
      text: rendered,
      fromCache: false,
      providerId: retryResponse.providerId,
      suggestedCooldownSeconds: _cooldownAfterSuccess(retryResponse.providerId),
    );
  }

  List<Map<String, dynamic>> _normalizeProductRows(
    List<Map<String, dynamic>> rows,
  ) {
    return rows
        .take(3)
        .map(
          (item) => {
            'name': (item['name'] ?? '-').toString(),
            'total_qty': ((item['total_qty'] as num?)?.toInt() ?? 0),
            'stock': ((item['stock'] as num?)?.toInt() ?? 0),
          },
        )
        .toList();
  }

  String _buildInsightFingerprint({
    required int income30,
    required int expense30,
    required int net30,
    required List<Map<String, dynamic>> topProducts,
    required List<Map<String, dynamic>> slowMovingProducts,
  }) {
    final payload = jsonEncode({
      'income30': income30,
      'expense30': expense30,
      'net30': net30,
      'top': topProducts,
      'slow': slowMovingProducts,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<String?> _tryGetCachedInsight(String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedText = prefs.getString(_cacheKeyText);
    final cachedHash = prefs.getString(_cacheKeyHash);
    final cachedEpoch = prefs.getInt(_cacheKeyEpoch);
    if (cachedText == null ||
        cachedText.trim().isEmpty ||
        cachedHash == null ||
        cachedEpoch == null) {
      return null;
    }
    if (cachedHash != fingerprint) {
      return null;
    }
    final age = DateTime.now().millisecondsSinceEpoch - cachedEpoch;
    if (age > _cacheTtl.inMilliseconds) {
      return null;
    }
    return cachedText;
  }

  Future<void> _saveCachedInsight({
    required String fingerprint,
    required String insight,
  }) async {
    final trimmed = insight.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKeyText, trimmed);
    await prefs.setString(_cacheKeyHash, fingerprint);
    await prefs.setInt(_cacheKeyEpoch, DateTime.now().millisecondsSinceEpoch);
  }

  String _buildInsightPrompt({
    required int income30,
    required int expense30,
    required int net30,
    required String topText,
    required String slowText,
  }) {
    return '''
Kamu adalah asisten keuangan UMKM toko kue.
Wajib pakai data yang diberikan. Jangan mengarang angka.
Balas HANYA dalam JSON valid dengan schema tepat:
{
  "insights": [
    {
      "temuan": "string pendek",
      "alasan_berbasis_data": "jelaskan dengan angka dari data",
      "aksi_nyata": "1 aksi operasional konkret 1-7 hari ke depan",
      "prioritas": "tinggi|sedang|rendah"
    }
  ]
}
Aturan:
- insights wajib tepat 3 item.
- Bahasa Indonesia sederhana, langsung.
- Tidak boleh ada teks di luar JSON.

Data:
- pemasukan_30_hari: Rp $income30
- pengeluaran_30_hari: Rp $expense30
- selisih_30_hari: Rp $net30
- produk_terlaris:
$topText
- produk_kurang_laris:
$slowText
''';
  }

  String _buildStrictRetryPrompt({
    required int income30,
    required int expense30,
    required int net30,
    required String topText,
    required String slowText,
  }) {
    return '''
Ulangi. Jawaban sebelumnya tidak sesuai.
WAJIB JSON valid saja, tanpa markdown.
Schema wajib:
{"insights":[{"temuan":"","alasan_berbasis_data":"","aksi_nyata":"","prioritas":"tinggi|sedang|rendah"}]}
Harus tepat 3 item di insights.

Gunakan hanya data ini:
- pemasukan_30_hari: Rp $income30
- pengeluaran_30_hari: Rp $expense30
- selisih_30_hari: Rp $net30
- produk_terlaris:
$topText
- produk_kurang_laris:
$slowText
''';
  }

  Map<String, dynamic>? _tryParseInsightJson(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    Map<String, dynamic>? decoded;
    try {
      final direct = jsonDecode(trimmed);
      if (direct is Map<String, dynamic>) {
        decoded = direct;
      } else if (direct is Map) {
        decoded = Map<String, dynamic>.from(direct);
      }
    } catch (_) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final candidate = trimmed.substring(start, end + 1);
        try {
          final loose = jsonDecode(candidate);
          if (loose is Map<String, dynamic>) {
            decoded = loose;
          } else if (loose is Map) {
            decoded = Map<String, dynamic>.from(loose);
          }
        } catch (_) {
          return null;
        }
      }
    }

    if (decoded == null) {
      return null;
    }

    final insightsRaw = decoded['insights'];
    if (insightsRaw is! List || insightsRaw.length != 3) {
      return null;
    }

    final normalized = <Map<String, String>>[];
    for (final row in insightsRaw) {
      final map =
          row is Map<String, dynamic>
              ? row
              : row is Map
              ? Map<String, dynamic>.from(row)
              : <String, dynamic>{};
      final temuan = (map['temuan'] ?? '').toString().trim();
      final alasan = (map['alasan_berbasis_data'] ?? '').toString().trim();
      final aksi = (map['aksi_nyata'] ?? '').toString().trim();
      final prioritas =
          (map['prioritas'] ?? '').toString().trim().toLowerCase();
      if (temuan.isEmpty ||
          alasan.isEmpty ||
          aksi.isEmpty ||
          prioritas.isEmpty) {
        return null;
      }
      if (prioritas != 'tinggi' &&
          prioritas != 'sedang' &&
          prioritas != 'rendah') {
        return null;
      }
      normalized.add({
        'temuan': temuan,
        'alasan_berbasis_data': alasan,
        'aksi_nyata': aksi,
        'prioritas': prioritas,
      });
    }

    return {'insights': normalized};
  }

  String _renderStructuredInsight(Map<String, dynamic> parsed) {
    final insights = parsed['insights'] as List<dynamic>? ?? const [];
    final lines = <String>[];
    for (var i = 0; i < insights.length; i++) {
      final row =
          insights[i] is Map<String, dynamic>
              ? insights[i] as Map<String, dynamic>
              : Map<String, dynamic>.from(insights[i] as Map);
      lines.add(
        '${i + 1}) [${(row['prioritas'] ?? '').toString().toUpperCase()}] '
        '${row['temuan']}\n'
        'Alasan: ${row['alasan_berbasis_data']}\n'
        'Aksi: ${row['aksi_nyata']}',
      );
    }
    return lines.join('\n\n').trim();
  }

  int _cooldownAfterSuccess(String providerId) {
    if (providerId == 'cache') {
      return 1;
    }
    if (providerId == 'groq') {
      return 3;
    }
    return 4;
  }

  Duration _nextRetryDelay(int attempt, {int? retryAfterSeconds}) {
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      return Duration(seconds: retryAfterSeconds.clamp(1, 30));
    }
    final safeAttempt = attempt < 1 ? 1 : attempt;
    final baseMs = (1000 * (1 << (safeAttempt - 1))).clamp(1000, 8000);
    final jitterMs = DateTime.now().microsecond % 400;
    return Duration(milliseconds: baseMs + jitterMs);
  }

  Future<Map<String, dynamic>> _requestProviderWithAdaptiveRetry(
    String providerId,
    String prompt, {
    required double temperature,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxProviderRetries; attempt++) {
      try {
        if (providerId == 'groq') {
          return await _requestGroq(prompt, temperature: temperature);
        }
        return await _requestGemini(prompt, temperature: temperature);
      } on AiRateLimitException catch (error) {
        lastError = error;
        if (error.isDailyLimit || attempt >= _maxProviderRetries) {
          rethrow;
        }
        await Future<void>.delayed(
          _nextRetryDelay(
            attempt,
            retryAfterSeconds:
                error.retryAfterSeconds > 0 ? error.retryAfterSeconds : null,
          ),
        );
      } on AiProviderTemporaryException catch (error) {
        lastError = error;
        if (attempt >= _maxProviderRetries) {
          rethrow;
        }
        await Future<void>.delayed(_nextRetryDelay(attempt));
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw const AiProviderTemporaryException('Provider AI gagal diproses.');
  }

  Future<_InsightProviderResponse> _requestInsightWithFallback(
    String prompt, {
    required double temperature,
  }) async {
    final order = String.fromEnvironment(
      'AI_INSIGHT_PROVIDER_ORDER',
      defaultValue: 'groq,gemini',
    );
    final requested =
        order
            .split(',')
            .map((entry) => entry.trim().toLowerCase())
            .where((entry) => entry.isNotEmpty)
            .toList();
    final providerIds =
        (requested.isEmpty ? const ['gemini', 'groq'] : requested)
            .where(_isProviderConfigured)
            .toList();

    Object? lastFallbackError;

    for (var i = 0; i < providerIds.length; i++) {
      final providerId = providerIds[i];
      final hasNext = i < providerIds.length - 1;
      try {
        if (providerId == 'groq') {
          final body = await _requestProviderWithAdaptiveRetry(
            'groq',
            prompt,
            temperature: temperature,
          );
          return _InsightProviderResponse(providerId: 'groq', body: body);
        }
        // default to gemini for unknown ids
        final body = await _requestProviderWithAdaptiveRetry(
          'gemini',
          prompt,
          temperature: temperature,
        );
        return _InsightProviderResponse(providerId: 'gemini', body: body);
      } on AiRateLimitException catch (error) {
        lastFallbackError = error;
        if (!hasNext) {
          rethrow;
        }
      } on AiProviderTemporaryException catch (error) {
        lastFallbackError = error;
        if (!hasNext) {
          rethrow;
        }
      }
    }

    if (lastFallbackError != null) {
      throw lastFallbackError;
    }
    throw Exception(
      'Provider AI belum dikonfigurasi. Set GEMINI_API_KEY atau GROQ_API_KEY saat build.',
    );
  }

  bool _isProviderConfigured(String providerId) {
    if (providerId == 'gemini') {
      return _apiKey.trim().isNotEmpty;
    }
    if (providerId == 'groq') {
      return _groqApiKey.trim().isNotEmpty;
    }
    return false;
  }

  Future<Map<String, dynamic>> _requestGemini(
    String prompt, {
    required double temperature,
  }) async {
    _validateGeminiInsightModel();

    if (_apiKey.trim().isEmpty) {
      throw const AiProviderTemporaryException(
        'GEMINI_API_KEY belum diset untuk provider utama.',
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey',
    );

    if (_debugLog) {
      developer.log('Prompt sent to Gemini:\n$prompt', name: 'AI_DEBUG');
    }

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': temperature,
                'maxOutputTokens': _maxOutputTokens,
              },
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      throw const AiProviderTemporaryException('Tidak ada koneksi internet.');
    } on HttpException {
      throw const AiProviderTemporaryException('Gagal menghubungi server AI.');
    } on FormatException {
      throw const AiProviderTemporaryException(
        'Format request AI tidak valid.',
      );
    } on TimeoutException {
      throw const AiProviderTemporaryException(
        'Permintaan AI timeout. Coba lagi.',
      );
    }

    if (response.statusCode >= 400) {
      if (response.statusCode == 429) {
        throw buildAiRateLimitExceptionFromResponse(response);
      }
      switch (response.statusCode) {
        case 400:
          throw Exception('Permintaan AI tidak valid. Coba lagi.');
        case 401:
          throw Exception('API key AI tidak valid atau belum benar.');
        case 403:
          throw Exception(
            'Akses AI ditolak. Periksa API key atau kuota project.',
          );
        case 404:
          throw Exception(
            'Model AI tidak ditemukan. Periksa konfigurasi model.',
          );
        case 500:
        case 502:
        case 503:
        case 504:
          throw const AiProviderTemporaryException(
            'Server AI sedang bermasalah. Coba beberapa saat lagi.',
          );
        default:
          throw Exception('Permintaan AI gagal (${response.statusCode}).');
      }
    }

    if (_debugLog) {
      developer.log('Raw Gemini response:\n${response.body}', name: 'AI_DEBUG');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AiProviderTemporaryException(
        'Respons AI tidak valid. Coba lagi.',
      );
    }
    final candidates = body['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('AI tidak mengembalikan saran.');
    }
    if (_debugLog) {
      developer.log(
        'Finish reasons: ${_extractFinishReasons(body)}',
        name: 'AI_DEBUG',
      );
    }
    return body;
  }

  void _validateGeminiInsightModel() {
    final model = _model.trim().toLowerCase();
    if (model.isEmpty) {
      throw const AiProviderTemporaryException(
        'GEMINI_INSIGHT_MODEL belum diset.',
      );
    }
    final isVisionFamily = model.contains('flash') || model.contains('pro');
    if (isVisionFamily) {
      throw AiProviderTemporaryException(
        'Model insight $_model diblokir: gunakan model teks (Gemma), bukan Flash/Pro.',
      );
    }
    final isGemmaTextModel = model.startsWith('gemma');
    if (!isGemmaTextModel) {
      throw AiProviderTemporaryException(
        'Model insight $_model tidak diizinkan. Gunakan model Gemma (contoh: gemma-3-12b).',
      );
    }
  }

  Future<Map<String, dynamic>> _requestGroq(
    String prompt, {
    required double temperature,
  }) async {
    if (_groqApiKey.trim().isEmpty) {
      throw const AiProviderTemporaryException(
        'GROQ_API_KEY belum diset untuk provider fallback.',
      );
    }

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_groqApiKey',
            },
            body: jsonEncode({
              'model': _groqModel,
              'temperature': temperature,
              'max_tokens': _maxOutputTokens,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      throw const AiProviderTemporaryException('Tidak ada koneksi internet.');
    } on HttpException {
      throw const AiProviderTemporaryException('Gagal menghubungi server AI.');
    } on FormatException {
      throw const AiProviderTemporaryException(
        'Format request AI tidak valid.',
      );
    } on TimeoutException {
      throw const AiProviderTemporaryException(
        'Permintaan AI timeout. Coba lagi.',
      );
    }

    if (response.statusCode >= 400) {
      if (response.statusCode == 429) {
        throw buildAiRateLimitExceptionFromResponse(response);
      }
      if (response.statusCode >= 500) {
        throw AiProviderTemporaryException(
          'Server AI sedang bermasalah (${response.statusCode}).',
        );
      }
      switch (response.statusCode) {
        case 400:
          throw Exception('Permintaan AI tidak valid. Coba lagi.');
        case 401:
          throw Exception('API key AI tidak valid atau belum benar.');
        case 403:
          throw Exception(
            'Akses AI ditolak. Periksa API key atau kuota project.',
          );
        case 404:
          throw Exception(
            'Model AI tidak ditemukan. Periksa konfigurasi model.',
          );
        default:
          throw Exception('Permintaan AI gagal (${response.statusCode}).');
      }
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AiProviderTemporaryException(
        'Respons AI tidak valid. Coba lagi.',
      );
    }
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('AI tidak mengembalikan saran.');
    }

    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': _extractGroqText(body)},
            ],
          },
          'finishReason': _extractGroqFinishReason(body),
        },
      ],
    };
  }

  String _extractGroqText(Map<String, dynamic> body) {
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return '';
    }
    final choice =
        choices.first is Map<String, dynamic>
            ? choices.first as Map<String, dynamic>
            : Map<String, dynamic>.from(choices.first as Map);
    final message =
        choice['message'] is Map<String, dynamic>
            ? choice['message'] as Map<String, dynamic>
            : choice['message'] is Map
            ? Map<String, dynamic>.from(choice['message'] as Map)
            : null;
    final content = message?['content'];
    if (content is String) {
      return content.trim();
    }
    return '';
  }

  String _extractGroqFinishReason(Map<String, dynamic> body) {
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return '';
    }
    final choice =
        choices.first is Map<String, dynamic>
            ? choices.first as Map<String, dynamic>
            : Map<String, dynamic>.from(choices.first as Map);
    final finishReason = choice['finish_reason'];
    return finishReason is String ? finishReason.trim().toUpperCase() : '';
  }

  String _extractJoinedText(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      return '';
    }

    final texts = <String>[];
    for (final candidate in candidates) {
      final candidateMap =
          candidate is Map<String, dynamic>
              ? candidate
              : Map<String, dynamic>.from(candidate as Map);
      final content = candidateMap['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        continue;
      }
      for (final part in parts) {
        final partMap =
            part is Map<String, dynamic>
                ? part
                : Map<String, dynamic>.from(part as Map);
        final text = partMap['text'];
        if (text is String && text.trim().isNotEmpty) {
          texts.add(text.trim());
        }
      }
    }

    return texts.join('\n\n').trim();
  }

  Set<String> _extractFinishReasons(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      return <String>{};
    }

    final reasons = <String>{};
    for (final candidate in candidates) {
      final candidateMap =
          candidate is Map<String, dynamic>
              ? candidate
              : Map<String, dynamic>.from(candidate as Map);
      final finishReason = candidateMap['finishReason'];
      if (finishReason is String && finishReason.trim().isNotEmpty) {
        reasons.add(finishReason.trim().toUpperCase());
      }
    }
    return reasons;
  }

  String _buildLocalFallbackInsight({
    required int income30,
    required int expense30,
    required int net30,
    required List<Map<String, dynamic>> topProducts,
    required List<Map<String, dynamic>> slowMovingProducts,
  }) {
    final topNames = topProducts
        .map((item) => '${item['name'] ?? '-'}')
        .take(2)
        .join(' dan ');
    final hasTop = topProducts.isNotEmpty;
    final slowNames = slowMovingProducts
        .map((item) => '${item['name'] ?? '-'}')
        .take(2)
        .join(' dan ');
    final hasSlow = slowMovingProducts.isNotEmpty;

    return '''
1) 🌟 Bintang Toko: ${hasTop ? '$topNames sedang paling laku. Pastikan stok dan bahan untuk produk ini aman dulu setiap pagi.' : 'Belum ada data produk paling laku. Catat produk yang paling cepat habis minggu ini.'}

2) 🔍 Evaluasi Produk Kurang Laris: ${hasSlow ? '$slowNames masih kurang laris. Coba tes 1 perubahan kecil selama 7 hari (porsi mini atau bonus topping) lalu lihat apakah penjualan naik.' : 'Belum ada produk yang terlihat kurang laris. Tetap pantau produk yang jarang dibeli agar tidak menumpuk.'}

3) 💰 Pantau Dompet: pemasukan Rp $income30, pengeluaran Rp $expense30, selisih Rp $net30. Tetapkan batas belanja bahan mingguan supaya uang kas tidak cepat habis.
'''.trim();
  }
}

int _parseRetryAfterSecondsFromHeader(String? retryAfterHeader) {
  if (retryAfterHeader == null || retryAfterHeader.trim().isEmpty) {
    return 60;
  }

  final trimmed = retryAfterHeader.trim();
  final secondsValue = int.tryParse(trimmed);
  if (secondsValue != null && secondsValue > 0) {
    return secondsValue;
  }

  final dateValue = DateTime.tryParse(trimmed);
  if (dateValue != null) {
    final seconds = dateValue.difference(DateTime.now().toUtc()).inSeconds;
    return seconds > 0 ? seconds : 60;
  }
  return 60;
}

int? _parseRetryDelaySeconds(String retryDelay) {
  final value = retryDelay.trim();
  if (value.isEmpty) {
    return null;
  }
  final match = RegExp(r'^(\d+)s$').firstMatch(value);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }
  return int.tryParse(value);
}
