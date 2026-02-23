import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/ocr_transaction_draft.dart';
import 'ai_insight_service.dart';

class AiOcrService {
  static const int maxItemsPerScan = 30;
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );

  Future<OcrBatchDraft> extractDraftFromImageBytes({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw Exception(
        'API key Gemini belum diset. Jalankan app dengan --dart-define=GEMINI_API_KEY=... ',
      );
    }

    final prompt = '''
Kamu mengekstrak daftar transaksi dari foto catatan buku keuangan UMKM.
Balas HANYA JSON object valid (tanpa markdown, tanpa teks tambahan).

Aturan:
- is_transaction: true jika foto berisi catatan transaksi keuangan yang masuk akal, false jika bukan transaksi jelas.
- reason: wajib diisi singkat saat is_transaction=false (contoh: "foto tidak berisi catatan transaksi yang jelas").
- Maksimal kembalikan $maxItemsPerScan transaksi yang paling jelas terbaca.
- Field tiap item transaksi:
  - type: "IN" atau "OUT"
  - amount: integer rupiah tanpa titik/koma (contoh 15000)
  - description: ringkas
  - category_hint: kata pendek kategori (contoh "Bahan Baku", "Operasional", "Penjualan Kue", "Pemasukan Lain")
  - date_iso: format yyyy-MM-dd jika terbaca, jika tidak isi string kosong
  - confidence: 0..100
  - raw_text: hasil bacaan OCR singkat item tersebut

JSON schema:
{
  "is_transaction": true,
  "reason": "",
  "transactions": [
    {
      "type": "IN|OUT",
      "amount": 0,
      "description": "",
      "category_hint": "",
      "date_iso": "",
      "confidence": 0,
      "raw_text": ""
    }
  ]
}
''';

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey',
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
                    {
                      'inlineData': {
                        'mimeType': mimeType,
                        'data': base64Encode(imageBytes),
                      },
                    },
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 420},
            }),
          )
          .timeout(const Duration(seconds: 25));
    } on SocketException {
      throw Exception('Tidak ada koneksi internet.');
    } on TimeoutException {
      throw Exception('Permintaan OCR AI timeout. Coba lagi.');
    } on HttpException {
      throw Exception('Gagal menghubungi server AI.');
    }

    if (response.statusCode == 429) {
      throw buildAiRateLimitExceptionFromResponse(response);
    }
    if (response.statusCode >= 400) {
      throw Exception('Permintaan OCR AI gagal (${response.statusCode}).');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = _extractJoinedText(body);
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

  String _extractJoinedText(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      return '';
    }
    final parts = <String>[];
    for (final candidate in candidates) {
      final candidateMap =
          candidate is Map<String, dynamic>
              ? candidate
              : Map<String, dynamic>.from(candidate as Map);
      final content = candidateMap['content'] as Map<String, dynamic>?;
      final candidateParts = content?['parts'] as List<dynamic>?;
      if (candidateParts == null) {
        continue;
      }
      for (final part in candidateParts) {
        final partMap =
            part is Map<String, dynamic>
                ? part
                : Map<String, dynamic>.from(part as Map);
        final text = partMap['text'];
        if (text is String && text.trim().isNotEmpty) {
          parts.add(text.trim());
        }
      }
    }
    return parts.join('\n').trim();
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
      throw Exception('Format respons OCR AI tidak valid.');
    }

    final jsonText = raw.substring(start, end + 1);
    final dynamic decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Format JSON OCR AI tidak valid.');
    }
    return decoded;
  }
}
