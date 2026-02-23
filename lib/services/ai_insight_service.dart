import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

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

class AiInsightService {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );
  static const bool _debugLog = _aiDebugLog;
  static const int _maxOutputTokens = 420;

  Future<String> generateOwnerInsight({
    required int income30,
    required int expense30,
    required int net30,
    required List<Map<String, dynamic>> topProducts,
    required List<Map<String, dynamic>> slowMovingProducts,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw Exception(
        'API key Gemini belum diset. Jalankan app dengan --dart-define=GEMINI_API_KEY=... ',
      );
    }

    final topText =
        topProducts.isEmpty
            ? '- Tidak ada data produk terlaris.'
            : topProducts
                .map((item) {
                  final name = item['name'] ?? '-';
                  final qty = item['total_qty'] ?? 0;
                  return '- $name: terjual $qty pcs';
                })
                .join('\n');

    final slowText =
        slowMovingProducts.isEmpty
            ? '- Tidak ada data produk kurang laris.'
            : slowMovingProducts
                .map((item) {
                  final name = item['name'] ?? '-';
                  final qty = item['total_qty'] ?? 0;
                  final stock = item['stock'] ?? 0;
                  return '- $name: terjual $qty pcs, stok saat ini $stock pcs';
                })
                .join('\n');

    final prompt = '''
Kamu adalah mentor bisnis toko kue lokal UMKM.
Gunakan bahasa sehari-hari yang ringan dan mudah dipahami pemilik toko.
DILARANG memakai istilah korporat/teknis seperti: margin, evaluasi operasional, perputaran stok, optimize, leverage.
Jangan mengarang angka baru, gunakan hanya data berikut:
- Pemasukan 30 hari: Rp $income30
- Pengeluaran 30 hari: Rp $expense30
- Selisih bersih 30 hari: Rp $net30
- Produk terlaris:
$topText
- Produk kurang laris:
$slowText

Format jawaban WAJIB:
1) 🌟 Bintang Toko: cara sederhana meningkatkan hasil dari produk terlaris.
2) 🔍 Evaluasi Produk Kurang Laris: dugaan penyebab masuk akal + 1 aksi sederhana 7 hari.
3) 💰 Pantau Dompet: 1 tips praktis menjaga uang kas agar tetap aman.
Setiap poin maksimal 32 kata.
Tanpa kalimat pembuka/penutup tambahan.
''';

    final firstBody = await _requestGemini(prompt, temperature: 0.25);
    final firstText = _extractJoinedText(firstBody);
    final firstReasons = _extractFinishReasons(firstBody);
    final needsRetry =
        firstText.isEmpty ||
        !_hasThreeNumberedPoints(firstText) ||
        _looksTooGeneric(firstText) ||
        firstReasons.contains('MAX_TOKENS');

    if (!needsRetry) {
      return firstText;
    }

    if (_debugLog) {
      developer.log(
        'AI response incomplete/generic, running one retry with stricter prompt.',
        name: 'AI_DEBUG',
      );
    }

    final retryPrompt = '''
Jawaban kamu sebelumnya belum sesuai format.
Ulangi tepat 3 poin, format ketat:
1) 🌟 Bintang Toko: ...
2) 🔍 Evaluasi Produk Kurang Laris: ...
3) 💰 Pantau Dompet: ...
Setiap poin maksimal 28 kata, bahasa sangat sederhana.

Wajib menyebut angka ini apa adanya:
- Pemasukan: Rp $income30
- Pengeluaran: Rp $expense30
- Selisih: Rp $net30
- Produk terlaris:
$topText
- Produk kurang laris:
$slowText

Jangan pakai istilah korporat.
Tanpa kalimat pembuka/penutup.
''';

    final retryBody = await _requestGemini(retryPrompt, temperature: 0.2);
    final retryText = _extractJoinedText(retryBody);

    if (retryText.isEmpty || !_hasThreeNumberedPoints(retryText)) {
      if (_debugLog) {
        developer.log(
          'Retry response still incomplete, using local deterministic fallback.',
          name: 'AI_DEBUG',
        );
      }
      return _buildLocalFallbackInsight(
        income30: income30,
        expense30: expense30,
        net30: net30,
        topProducts: topProducts,
        slowMovingProducts: slowMovingProducts,
      );
    }

    return retryText;
  }

  Future<Map<String, dynamic>> _requestGemini(
    String prompt, {
    required double temperature,
  }) async {
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
      throw Exception('Tidak ada koneksi internet.');
    } on HttpException {
      throw Exception('Gagal menghubungi server AI.');
    } on FormatException {
      throw Exception('Format request AI tidak valid.');
    } on TimeoutException {
      throw Exception('Permintaan AI timeout. Coba lagi.');
    }

    if (response.statusCode >= 400) {
      if (response.statusCode == 429) {
        throw buildAiRateLimitExceptionFromResponse(response);
      }
      throw Exception('Permintaan AI gagal (${response.statusCode}).');
    }

    if (_debugLog) {
      developer.log('Raw Gemini response:\n${response.body}', name: 'AI_DEBUG');
    }

    final Map<String, dynamic> body = jsonDecode(response.body);
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

  bool _hasThreeNumberedPoints(String text) {
    final normalized = text.toLowerCase();
    final has1 = RegExp(r'(^|\n)\s*1[)\.]').hasMatch(normalized);
    final has2 = RegExp(r'(^|\n)\s*2[)\.]').hasMatch(normalized);
    final has3 = RegExp(r'(^|\n)\s*3[)\.]').hasMatch(normalized);
    return has1 && has2 && has3;
  }

  bool _looksTooGeneric(String text) {
    final normalized = text.toLowerCase().trim();
    return normalized.contains('berikut 3 saran praktis');
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
