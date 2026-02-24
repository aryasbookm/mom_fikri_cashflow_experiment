import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/ocr_transaction_draft.dart';
import '../ai_insight_service.dart';
import 'ai_vision_provider.dart';

class GroqVisionProvider implements AiVisionProvider {
  static const int maxItemsPerScan = 30;
  static const String _apiKey = String.fromEnvironment('GROQ_API_KEY');
  static const String _model = String.fromEnvironment(
    'GROQ_VISION_MODEL',
    defaultValue: 'llama-3.2-11b-vision-preview',
  );

  @override
  String get providerId => 'groq';

  @override
  Future<OcrBatchDraft> extractDraftFromImageBytes({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw const AiProviderTemporaryException(
        'GROQ_API_KEY belum diset untuk fallback provider.',
      );
    }

    final prompt = '''
Kamu mengekstrak daftar transaksi dari foto catatan buku keuangan UMKM.
Balas HANYA JSON object valid (tanpa markdown, tanpa teks tambahan).

Aturan:
- is_transaction: true jika foto berisi catatan transaksi keuangan yang masuk akal, false jika bukan transaksi jelas.
- reason: wajib diisi singkat saat is_transaction=false.
- Maksimal kembalikan $maxItemsPerScan transaksi yang paling jelas terbaca.
- Field tiap item transaksi:
  - type: "IN" atau "OUT"
  - amount: integer rupiah tanpa titik/koma
  - description: ringkas
  - category_hint: kata pendek kategori
  - date_iso: format yyyy-MM-dd jika terbaca, jika tidak isi string kosong
  - confidence: 0..100
  - raw_text: hasil bacaan OCR singkat item tersebut
''';

    final dataUri = 'data:$mimeType;base64,${base64Encode(imageBytes)}';

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'temperature': 0.1,
              'max_tokens': 420,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': prompt},
                    {
                      'type': 'image_url',
                      'image_url': {'url': dataUri},
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 25));
    } on SocketException {
      throw const AiProviderTemporaryException('Tidak ada koneksi internet.');
    } on TimeoutException {
      throw const AiProviderTemporaryException(
        'Permintaan OCR AI timeout. Coba lagi.',
      );
    } on HttpException {
      throw const AiProviderTemporaryException('Gagal menghubungi server AI.');
    }

    if (response.statusCode == 429) {
      throw buildAiRateLimitExceptionFromResponse(response);
    }
    if (response.statusCode >= 400) {
      if (response.statusCode >= 500) {
        throw AiProviderTemporaryException(
          'Server AI sedang sibuk (${response.statusCode}).',
        );
      }
      switch (response.statusCode) {
        case 400:
          throw Exception('Permintaan OCR tidak valid. Coba foto ulang.');
        case 401:
          throw Exception('API key AI tidak valid atau belum benar.');
        case 403:
          throw Exception('Akses OCR AI ditolak. Periksa API key/kuota.');
        case 404:
          throw Exception('Model OCR AI tidak ditemukan.');
        default:
          throw Exception('Permintaan OCR AI gagal (${response.statusCode}).');
      }
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = _extractText(body);
    if (text.isEmpty) {
      throw Exception('AI tidak mengembalikan data OCR.');
    }

    final parsed = _parseJsonObject(text);
    final batch = OcrBatchDraft.fromJson(parsed);
    if (!batch.isTransaction) {
      final reason =
          batch.reason.isNotEmpty
              ? batch.reason
              : 'Foto ini sepertinya bukan catatan transaksi.';
      throw Exception(reason);
    }

    final filtered =
        batch.transactions
            .where((item) => item.amount > 0)
            .where((item) => item.description.trim().length >= 3)
            .where((item) => item.rawText.trim().length >= 3)
            .take(maxItemsPerScan)
            .toList();

    if (filtered.isEmpty) {
      throw Exception(
        'Transaksi valid tidak ditemukan. Coba foto lebih jelas atau lebih fokus.',
      );
    }
    return OcrBatchDraft(
      isTransaction: true,
      reason: '',
      transactions: filtered,
    );
  }

  String _extractText(Map<String, dynamic> body) {
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return '';
    }
    final choice =
        choices.first is Map<String, dynamic>
            ? choices.first as Map<String, dynamic>
            : Map<String, dynamic>.from(choices.first as Map);
    final message = choice['message'];
    if (message is! Map) {
      return '';
    }
    final content = message['content'];
    if (content is String) {
      return content.trim();
    }
    if (content is List) {
      final parts = <String>[];
      for (final segment in content) {
        final map =
            segment is Map<String, dynamic>
                ? segment
                : segment is Map
                ? Map<String, dynamic>.from(segment)
                : null;
        final text = map?['text'];
        if (text is String && text.trim().isNotEmpty) {
          parts.add(text.trim());
        }
      }
      return parts.join('\n').trim();
    }
    return '';
  }

  Map<String, dynamic> _parseJsonObject(String text) {
    var raw = text.trim();
    if (raw.startsWith('```')) {
      raw = raw.replaceAll(RegExp(r'^```json\s*'), '');
      raw = raw.replaceAll(RegExp(r'^```\s*'), '');
      raw = raw.replaceAll(RegExp(r'\s*```$'), '');
    }

    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      throw Exception(
        'AI tidak mengembalikan format transaksi yang valid. Coba foto catatan transaksi yang lebih jelas.',
      );
    }

    final jsonText = raw.substring(start, end + 1);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'AI mengembalikan data OCR yang tidak terbaca sistem. Coba foto ulang.',
      );
    }
    return decoded;
  }
}
