import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

class AiInsightService {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );
  static const bool _debugLog = bool.fromEnvironment(
    'AI_DEBUG_LOG',
    defaultValue: false,
  );
  static const int _maxOutputTokens = 420;

  Future<String> generateOwnerInsight({
    required int income30,
    required int expense30,
    required int net30,
    required List<Map<String, dynamic>> slowMovingProducts,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw Exception(
        'API key Gemini belum diset. Jalankan app dengan --dart-define=GEMINI_API_KEY=... ',
      );
    }

    final slowText =
        slowMovingProducts.isEmpty
            ? '- Tidak ada data produk lambat.'
            : slowMovingProducts
                .map((item) {
                  final name = item['name'] ?? '-';
                  final qty = item['total_qty'] ?? 0;
                  final stock = item['stock'] ?? 0;
                  return '- $name: terjual $qty pcs, stok saat ini $stock pcs';
                })
                .join('\n');

    final prompt = '''
Kamu adalah asisten bisnis untuk UMKM toko kue.
Berikan tepat 3 saran praktis, singkat, dan dapat dieksekusi.
Gunakan Bahasa Indonesia yang sederhana.
Jangan mengarang angka baru, gunakan hanya data berikut:
- Pemasukan 30 hari: Rp $income30
- Pengeluaran 30 hari: Rp $expense30
- Selisih bersih 30 hari: Rp $net30
- Produk kurang laris:
$slowText

Format jawaban WAJIB:
1) ...
2) ...
3) ...
Tanpa kalimat pembuka tambahan.
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
Jawaban kamu sebelumnya tidak lengkap.
Berikan ulang dengan format ketat:
1) ...
2) ...
3) ...
Setiap poin maksimal 25 kata.

Wajib menyebut angka ini apa adanya:
- Pemasukan: Rp $income30
- Pengeluaran: Rp $expense30
- Selisih: Rp $net30
- Produk kurang laris:
$slowText

Tanpa kalimat pembuka.
''';

    final retryBody = await _requestGemini(retryPrompt, temperature: 0.2);
    final retryText = _extractJoinedText(retryBody);

    if (retryText.isEmpty || !_hasThreeNumberedPoints(retryText)) {
      throw Exception('Respons AI terpotong/tidak lengkap. Coba tekan lagi.');
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
    return normalized.contains('1)') &&
        normalized.contains('2)') &&
        normalized.contains('3)');
  }

  bool _looksTooGeneric(String text) {
    final normalized = text.toLowerCase().trim();
    return normalized.contains('berikut 3 saran praktis');
  }
}
