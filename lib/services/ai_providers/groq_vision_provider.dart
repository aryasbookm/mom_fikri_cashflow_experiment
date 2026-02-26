import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/ocr_transaction_draft.dart';
import '../ai_insight_service.dart';
import 'ai_vision_provider.dart';
import 'ocr_post_processing.dart';

class GroqVisionProvider implements AiVisionProvider {
  static const int maxItemsPerScan = 30;
  static const int _maxOutputTokens = 2500;
  static const String _apiKey = String.fromEnvironment('GROQ_API_KEY');
  static const String _defaultVisionModel =
      'meta-llama/llama-4-scout-17b-16e-instruct';
  static const String _model = String.fromEnvironment(
    'GROQ_VISION_MODEL',
    defaultValue: _defaultVisionModel,
  );

  @override
  String get providerId => 'groq';

  @override
  Duration? get requestTimeout => const Duration(seconds: 10);

  @override
  Future<OcrBatchDraft> extractDraftFromImageBytes({
    required List<int> imageBytes,
    required String mimeType,
    OcrProviderStageCallback? onProviderEvent,
  }) async {
    const stage = 'vision_pass';
    onProviderEvent?.call(stage, 'try', null);
    if (_apiKey.trim().isEmpty) {
      throw const AiProviderTemporaryException(
        'GROQ_API_KEY belum diset untuk fallback provider.',
      );
    }

    final prompt = '''
Kamu mengekstrak daftar transaksi dari foto catatan buku keuangan UMKM toko kue "Mom Fiqry Cake".
Balas HANYA JSON object valid (tanpa markdown, tanpa teks tambahan).

Aturan:
- is_transaction: true jika foto berisi catatan transaksi keuangan yang masuk akal, false jika bukan transaksi jelas.
- Jika ada minimal 1 pasangan item + nominal yang masuk akal, WAJIB set `is_transaction=true`.
- reason: wajib diisi singkat saat is_transaction=false.
- Maksimal kembalikan $maxItemsPerScan transaksi yang paling jelas terbaca.
- Jika ada nominal seperti "20.000 + 20.000", isi `amount` sebagai total akhirnya (40000).
- Baris ringkasan seperti Total/Jumlah/Uang Bersih/Saldo Akhir bukan transaksi; pindahkan ke summary.notes_found atau ignored_lines.
- Field tiap item transaksi:
  - type: "IN" atau "OUT"
  - amount: integer rupiah tanpa titik/koma
  - description: ringkas
  - category_hint: kata pendek kategori
  - date_iso: format yyyy-MM-dd jika terbaca, jika tidak isi string kosong
  - date_source: "explicit" | "inferred" | "unknown"
  - confidence: 0..100
  - raw_text: hasil bacaan OCR singkat item tersebut
  - needs_review: true jika ada kemungkinan typo/tidak yakin
  - warning: alasan singkat jika needs_review=true
- Jika tanggal item ditebak dari konteks (bukan tertulis jelas), set date_source="inferred" dan WAJIB needs_review=true.
- Gunakan date_source="explicit" hanya jika tanggal tertulis jelas pada catatan.
- Sertakan summary:
  - date_detected: tanggal yang terbaca (boleh kosong)
  - notes_found: info non-transaksi penting (mis. Uang Bersih/Total)
- ignored_lines: daftar teks yang terbaca tapi bukan transaksi.
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
              'max_tokens': _maxOutputTokens,
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
          .timeout(const Duration(seconds: 35));
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
      final detail = _extractErrorDetail(response.body);
      switch (response.statusCode) {
        case 400:
          throw Exception(
            '[Groq] Permintaan OCR ditolak (400). ${detail.isNotEmpty ? detail : 'Periksa format file (JPG/PNG/WEBP), ukuran gambar, atau konfigurasi model.'}'
            '${detail.toLowerCase().contains('decommissioned') ? ' Set GROQ_VISION_MODEL ke $_defaultVisionModel.' : ''}',
          );
        case 401:
          throw Exception(
            '[Groq] API key AI tidak valid atau belum benar. ${detail.isNotEmpty ? detail : ''}'
                .trim(),
          );
        case 403:
          throw Exception(
            '[Groq] Akses OCR AI ditolak. ${detail.isNotEmpty ? detail : 'Periksa API key/kuota.'}',
          );
        case 404:
          throw Exception(
            '[Groq] Model OCR AI tidak ditemukan. ${detail.isNotEmpty ? detail : ''}'
                .trim(),
          );
        default:
          throw Exception(
            '[Groq] Permintaan OCR AI gagal (${response.statusCode}). ${detail.isNotEmpty ? detail : ''}'
                .trim(),
          );
      }
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = _extractText(body);
    if (text.isEmpty) {
      onProviderEvent?.call(stage, 'error', 'AI tidak mengembalikan data OCR.');
      throw Exception('AI tidak mengembalikan data OCR.');
    }

    final parsed = _parseJsonObject(text);
    final batch = OcrBatchDraft.fromJson(parsed);
    if (!batch.isTransaction && batch.transactions.isEmpty) {
      final reason =
          batch.reason.isNotEmpty
              ? batch.reason
              : 'Foto ini sepertinya bukan catatan transaksi.';
      throw Exception(reason);
    }

    final processed = OcrPostProcessor.normalize(
      batch: batch,
      maxItems: maxItemsPerScan,
      forceReview: !batch.isTransaction,
    );
    final filtered = processed.transactions;

    if (filtered.isEmpty) {
      onProviderEvent?.call(
        stage,
        'error',
        'Transaksi valid tidak ditemukan. Coba foto lebih jelas atau lebih fokus.',
      );
      throw Exception(
        'Transaksi valid tidak ditemukan. Coba foto lebih jelas atau lebih fokus.',
      );
    }
    onProviderEvent?.call(stage, 'ok', null);
    return OcrBatchDraft(
      isTransaction: true,
      reason: '',
      transactions: filtered,
      detectedDate: batch.detectedDate,
      notesFound: processed.notesFound,
      ignoredLines: processed.ignoredLines,
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
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw Exception(
        'Respons OCR AI terpotong/tidak lengkap. Coba tekan "Coba Lagi".',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'AI mengembalikan data OCR yang tidak terbaca sistem. Coba foto ulang.',
      );
    }
    return decoded;
  }

  String _extractErrorDetail(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = (error['message'] ?? '').toString().trim();
          if (message.isNotEmpty) {
            return message;
          }
        }
      }
    } catch (_) {}
    return '';
  }
}
