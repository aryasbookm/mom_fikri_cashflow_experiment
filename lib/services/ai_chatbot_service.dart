import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_insight_service.dart';
import 'ai_providers/ai_vision_provider.dart';

class AiChatMessage {
  const AiChatMessage({required this.role, required this.text});

  final String role; // "user" | "assistant"
  final String text;
}

class AiChatReply {
  const AiChatReply({
    required this.text,
    required this.providerId,
    required this.fromCache,
    required this.suggestedCooldownSeconds,
  });

  final String text;
  final String providerId;
  final bool fromCache;
  final int suggestedCooldownSeconds;
}

class AiChatbotService {
  static const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _groqApiKey = String.fromEnvironment('GROQ_API_KEY');
  static const String _geminiModel = String.fromEnvironment(
    'GEMINI_CHAT_MODEL',
    defaultValue: 'gemma-3-12b',
  );
  static const String _groqModel = String.fromEnvironment(
    'GROQ_CHAT_MODEL',
    defaultValue: 'llama-3.1-8b-instant',
  );
  static const int _maxOutputTokens = 700;
  static const int _maxHistoryMessages = 8;
  static const int _maxProviderRetries = 2;
  static const Duration _cacheTtl = Duration(minutes: 10);

  static const String _cacheKeyText = 'ai_chat_cache_text_v1';
  static const String _cacheKeyHash = 'ai_chat_cache_hash_v1';
  static const String _cacheKeyEpoch = 'ai_chat_cache_epoch_v1';

  Future<AiChatReply> askFinancialAssistant({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    List<AiChatMessage> history = const [],
  }) async {
    final boundedHistory =
        history
            .where((m) => m.text.trim().isNotEmpty)
            .toList()
            .reversed
            .take(_maxHistoryMessages)
            .toList()
            .reversed
            .toList();

    final fingerprint = _buildFingerprint(
      question: question,
      financeSnapshot: financeSnapshot,
      history: boundedHistory,
    );

    final cached = await _tryGetCached(fingerprint);
    if (cached != null) {
      return AiChatReply(
        text: cached,
        providerId: 'cache',
        fromCache: true,
        suggestedCooldownSeconds: 1,
      );
    }

    final prompt = _buildBoundedPrompt(
      question: question,
      financeSnapshot: financeSnapshot,
      history: boundedHistory,
    );

    final response = await _requestWithFallback(prompt);
    final cleaned = response.text.trim();
    if (cleaned.isEmpty) {
      throw const AiProviderTemporaryException('Jawaban AI kosong. Coba lagi.');
    }

    await _saveCache(fingerprint: fingerprint, text: cleaned);
    return AiChatReply(
      text: cleaned,
      providerId: response.providerId,
      fromCache: false,
      suggestedCooldownSeconds: response.providerId == 'groq' ? 3 : 4,
    );
  }

  String _buildBoundedPrompt({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    required List<AiChatMessage> history,
  }) {
    final safeQuestion = question.trim();
    final hasCatalog = financeSnapshot.any(
      (row) => (row['type'] ?? '').toString() == 'product_catalog',
    );
    final snapshotLimit = hasCatalog ? 140 : 60;
    final snapshotText =
        financeSnapshot.isEmpty
            ? '- Data belum tersedia.'
            : financeSnapshot
                .take(snapshotLimit)
                .map((row) => jsonEncode(row))
                .join('\n');

    final historyText =
        history.isEmpty
            ? '- (kosong)'
            : history.map((m) => '- ${m.role}: ${m.text.trim()}').join('\n');

    return '''
Kamu adalah asisten keuangan UMKM untuk toko kue.
Aturan keras:
- Jawaban hanya boleh terkait data keuangan toko pada konteks di bawah.
- Jika pertanyaan di luar konteks (cuaca, politik, umum), jawab: "Saya hanya bisa membantu analisis data keuangan toko Anda.".
- Jangan mengarang angka.
- Jawaban ringkas: maksimal 4 poin atau 1 paragraf pendek.
- Sertakan dasar data (tanggal/nominal/tren) jika ada.
- Data `top_product` dan `slow_product` adalah sampel, bukan seluruh katalog.
- Data `product_catalog` adalah stok saat ini. Jangan campur `stock_now` dengan `total_qty` penjualan.
- Data `income_category_30d` dan `expense_category_30d` adalah agregat kategori 30 hari.
- Jika data tidak cukup untuk jawaban pasti, katakan "data belum cukup" dan sebut data tambahan yang dibutuhkan.

Konteks data (agregat/transaksi ringkas):
$snapshotText

Riwayat percakapan (terbatas):
$historyText

Pertanyaan user:
$safeQuestion
''';
  }

  String _buildFingerprint({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    required List<AiChatMessage> history,
  }) {
    final payload = jsonEncode({
      'q': question.trim(),
      'snapshot': financeSnapshot,
      'history':
          history
              .map((m) => {'role': m.role.trim(), 'text': m.text.trim()})
              .toList(),
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<String?> _tryGetCached(String fingerprint) async {
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
    final ageMs = DateTime.now().millisecondsSinceEpoch - cachedEpoch;
    if (ageMs > _cacheTtl.inMilliseconds) {
      return null;
    }
    return cachedText;
  }

  Future<void> _saveCache({
    required String fingerprint,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKeyText, trimmed);
    await prefs.setString(_cacheKeyHash, fingerprint);
    await prefs.setInt(_cacheKeyEpoch, DateTime.now().millisecondsSinceEpoch);
  }

  Future<_ChatProviderResponse> _requestWithFallback(String prompt) async {
    final order = String.fromEnvironment(
      'AI_CHAT_PROVIDER_ORDER',
      defaultValue: 'groq,gemini',
    );
    final providerIds =
        order
            .split(',')
            .map((v) => v.trim().toLowerCase())
            .where((v) => v.isNotEmpty)
            .where(_isProviderConfigured)
            .toList();

    Object? lastError;
    for (var i = 0; i < providerIds.length; i++) {
      final providerId = providerIds[i];
      final hasNext = i < providerIds.length - 1;
      try {
        final text = await _requestProviderWithRetry(providerId, prompt);
        return _ChatProviderResponse(providerId: providerId, text: text);
      } on AiRateLimitException catch (error) {
        lastError = error;
        if (!hasNext) {
          rethrow;
        }
      } on AiProviderTemporaryException catch (error) {
        lastError = error;
        if (!hasNext) {
          rethrow;
        }
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw const AiProviderTemporaryException(
      'Provider chat belum dikonfigurasi. Set GROQ_API_KEY atau GEMINI_API_KEY.',
    );
  }

  bool _isProviderConfigured(String providerId) {
    if (providerId == 'groq') {
      return _groqApiKey.trim().isNotEmpty;
    }
    if (providerId == 'gemini') {
      return _geminiApiKey.trim().isNotEmpty;
    }
    return false;
  }

  Future<String> _requestProviderWithRetry(
    String providerId,
    String prompt,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxProviderRetries; attempt++) {
      try {
        if (providerId == 'groq') {
          return await _requestGroq(prompt);
        }
        return await _requestGemini(prompt);
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
    throw lastError ??
        const AiProviderTemporaryException('Chat AI gagal diproses.');
  }

  Duration _nextRetryDelay(int attempt, {int? retryAfterSeconds}) {
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      return Duration(seconds: retryAfterSeconds.clamp(1, 30));
    }
    final baseMs = (1000 * (1 << (attempt - 1))).clamp(1000, 8000);
    final jitterMs = DateTime.now().millisecond % 400;
    return Duration(milliseconds: baseMs + jitterMs);
  }

  void _validateGeminiChatModel() {
    final model = _geminiModel.trim().toLowerCase();
    if (model.isEmpty) {
      throw const AiProviderTemporaryException(
        'GEMINI_CHAT_MODEL belum diset.',
      );
    }
    if (model.contains('flash') || model.contains('pro')) {
      throw AiProviderTemporaryException(
        'Model chat $_geminiModel diblokir: gunakan model teks (Gemma), bukan Flash/Pro.',
      );
    }
    if (!model.startsWith('gemma')) {
      throw AiProviderTemporaryException(
        'Model chat $_geminiModel tidak diizinkan. Gunakan model Gemma.',
      );
    }
  }

  Future<String> _requestGemini(String prompt) async {
    _validateGeminiChatModel();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$_geminiApiKey',
    );

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
                'temperature': 0.25,
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
      if (response.statusCode >= 500) {
        throw const AiProviderTemporaryException(
          'Server AI sedang bermasalah. Coba beberapa saat lagi.',
        );
      }
      throw Exception('Permintaan AI gagal (${response.statusCode}).');
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
      throw const AiProviderTemporaryException(
        'AI tidak mengembalikan jawaban.',
      );
    }

    final candidate =
        candidates.first is Map<String, dynamic>
            ? candidates.first as Map<String, dynamic>
            : Map<String, dynamic>.from(candidates.first as Map);
    final content =
        candidate['content'] is Map<String, dynamic>
            ? candidate['content'] as Map<String, dynamic>
            : candidate['content'] is Map
            ? Map<String, dynamic>.from(candidate['content'] as Map)
            : <String, dynamic>{};
    final parts = content['parts'] as List<dynamic>? ?? const [];
    final texts =
        parts
            .map(
              (p) =>
                  p is Map<String, dynamic>
                      ? (p['text'] ?? '').toString().trim()
                      : p is Map
                      ? (Map<String, dynamic>.from(p)['text'] ?? '')
                          .toString()
                          .trim()
                      : '',
            )
            .where((v) => v.isNotEmpty)
            .toList();

    return texts.join('\n').trim();
  }

  Future<String> _requestGroq(String prompt) async {
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
              'temperature': 0.2,
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
      throw Exception('Permintaan AI gagal (${response.statusCode}).');
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
      throw const AiProviderTemporaryException(
        'AI tidak mengembalikan jawaban.',
      );
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
            : <String, dynamic>{};
    return (message['content'] ?? '').toString().trim();
  }
}

class _ChatProviderResponse {
  const _ChatProviderResponse({required this.providerId, required this.text});

  final String providerId;
  final String text;
}
