import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/ocr_transaction_draft.dart';
import '../ai_insight_service.dart';
import 'ai_vision_provider.dart';
import 'ocr_post_processing.dart';

class GeminiVisionProvider implements AiVisionProvider {
  static const int maxItemsPerScan = 30;
  static const int _maxVisionOutputTokens = 3200;
  static const int _maxStructuringOutputTokens = 2500;
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _defaultModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );
  static const String _defaultTextStructuringModelChain =
      'gemma-3-12b-it,gemini-2.5-flash-lite';
  static const String _textStructuringModelChain = String.fromEnvironment(
    'GEMINI_OCR_TEXT_MODEL_CHAIN',
    defaultValue: _defaultTextStructuringModelChain,
  );

  GeminiVisionProvider({String? model})
    : _model =
          (model == null || model.trim().isEmpty)
              ? _defaultModel
              : model.trim();

  final String _model;

  @override
  String get providerId => _model;

  @override
  Duration? get requestTimeout {
    final normalized = _model.toLowerCase();
    if (normalized.contains('flash-lite')) {
      return const Duration(seconds: 12);
    }
    // Vision high-end models need more breathing room to return valid JSON.
    return const Duration(seconds: 25);
  }

  @override
  Future<OcrBatchDraft> extractDraftFromImageBytes({
    required List<int> imageBytes,
    required String mimeType,
    OcrProviderStageCallback? onProviderEvent,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw Exception(
        'API key Gemini belum diset. Jalankan app dengan --dart-define=GEMINI_API_KEY=... ',
      );
    }

    if (_isLiteModel(_model)) {
      final singlePassJson = await _runSinglePassLiteJson(
        imageBytes: imageBytes,
        mimeType: mimeType,
        onProviderEvent: onProviderEvent,
      );
      final parsed = _parseJsonObject(singlePassJson);
      return _finalizeBatchFromParsed(parsed);
    }

    final rawText = await _runVisionPass(
      imageBytes: imageBytes,
      mimeType: mimeType,
      onProviderEvent: onProviderEvent,
    );
    if (rawText.trim().isEmpty) {
      throw Exception('AI tidak mengembalikan data OCR.');
    }
    final structuredText = await _runStructuringPass(
      rawText: rawText,
      onProviderEvent: onProviderEvent,
    );
    if (structuredText.trim().isEmpty) {
      throw Exception('AI tidak mengembalikan data OCR terstruktur.');
    }

    final parsed = _parseJsonObject(structuredText);
    return _finalizeBatchFromParsed(parsed);
  }

  bool _isLiteModel(String model) => model.toLowerCase().contains('flash-lite');

  OcrBatchDraft _finalizeBatchFromParsed(Map<String, dynamic> parsed) {
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
      throw Exception(
        'Transaksi valid tidak ditemukan. Coba foto lebih jelas atau lebih fokus.',
      );
    }
    return OcrBatchDraft(
      isTransaction: true,
      reason: '',
      transactions: filtered,
      detectedDate: batch.detectedDate,
      notesFound: processed.notesFound,
      ignoredLines: processed.ignoredLines,
    );
  }

  Future<String> _runSinglePassLiteJson({
    required List<int> imageBytes,
    required String mimeType,
    OcrProviderStageCallback? onProviderEvent,
  }) async {
    const stage = 'single_pass';
    onProviderEvent?.call(stage, 'try', null);

    final prompt = '''
Ekstrak transaksi dari foto catatan keuangan UMKM "Mom Fiqry Cake".
Keluarkan HANYA JSON object valid, tanpa markdown dan tanpa teks lain.

Aturan inti:
- Kembalikan SEMUA kandidat transaksi yang punya nominal (maksimal $maxItemsPerScan item).
- Jika ada minimal 1 pasangan item + nominal masuk akal => is_transaction=true.
- Nominal wajib integer rupiah tanpa titik/koma.
- Nominal gabungan (contoh "20.000 + 20.000") => amount = total akhir (40000).
- Baris Total/Jumlah/Uang Bersih/Saldo Akhir bukan transaksi => pindah ke summary.notes_found atau ignored_lines.
- Jika tanggal tidak tertulis jelas tapi ditebak konteks => date_source="inferred" dan needs_review=true.
- Jika baris terlihat transaksi tapi kurang yakin, tetap masukkan sebagai item dengan needs_review=true dan warning yang jelas.

Schema wajib:
{
  "summary": {"date_detected": "", "notes_found": [{"label": "", "value": ""}]},
  "is_transaction": true,
  "reason": "",
  "ignored_lines": [""],
  "transactions": [{
    "type": "IN|OUT",
    "amount": 0,
    "description": "",
    "category_hint": "",
    "date_iso": "",
    "date_source": "explicit|inferred|unknown",
    "confidence": 0,
    "raw_text": "",
    "needs_review": false,
    "warning": ""
  }]
}
''';

    try {
      final response = await _postGenerateContent(
        model: _model,
        contents: [
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
        generationConfig: {
          'temperature': 0.1,
          'maxOutputTokens': _maxStructuringOutputTokens,
          'responseMimeType': 'application/json',
        },
      );
      _throwIfVisionResponseError(response);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final text = _extractJoinedText(body);
      onProviderEvent?.call(stage, 'ok', null);
      return text;
    } catch (error) {
      onProviderEvent?.call(stage, 'error', error.toString());
      rethrow;
    }
  }

  Future<String> _runVisionPass({
    required List<int> imageBytes,
    required String mimeType,
    OcrProviderStageCallback? onProviderEvent,
  }) async {
    const stage = 'vision_pass';
    onProviderEvent?.call(stage, 'try', null);
    final prompt = '''
Tugas: OCR mentah dari foto catatan keuangan UMKM "Mom Fiqry Cake".
Keluarkan teks mentah saja (plain text), tanpa JSON, tanpa markdown, tanpa penjelasan.

Aturan:
- Salin baris yang terbaca seakurat mungkin.
- Pertahankan urutan baris dari atas ke bawah.
- Jangan menambah interpretasi.
- Jika ada bagian tidak jelas, tulis apa adanya.
''';

    try {
      final response = await _postGenerateContent(
        model: _model,
        contents: [
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
        generationConfig: _visionGenerationConfigForModel(),
      );
      _throwIfVisionResponseError(response);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final text = _extractJoinedText(body);
      onProviderEvent?.call(stage, 'ok', null);
      return text;
    } catch (error) {
      onProviderEvent?.call(stage, 'error', error.toString());
      rethrow;
    }
  }

  Future<String> _runStructuringPass({
    required String rawText,
    OcrProviderStageCallback? onProviderEvent,
  }) async {
    final models = _textStructuringModelsFromEnvironment();
    Object? lastError;

    for (final model in models) {
      final stage = 'text_structuring_pass:$model';
      try {
        onProviderEvent?.call(stage, 'try', null);
        final prompt = '''
Ubah OCR mentah berikut menjadi JSON transaksi keuangan.
Keluarkan HANYA JSON object valid, tanpa markdown dan tanpa teks lain.

Aturan inti:
- Maksimal $maxItemsPerScan transaksi paling jelas.
- Jika ada minimal 1 pasangan item + nominal masuk akal => is_transaction=true.
- Nominal wajib integer rupiah tanpa titik/koma.
- Nominal gabungan (contoh "20.000 + 20.000") => amount = total akhir (40000).
- Baris Total/Jumlah/Uang Bersih/Saldo Akhir bukan transaksi => pindah ke summary.notes_found atau ignored_lines.
- Jika tanggal tidak tertulis jelas tapi ditebak konteks => date_source="inferred" dan needs_review=true.

Schema wajib:
{
  "summary": {"date_detected": "", "notes_found": [{"label": "", "value": ""}]},
  "is_transaction": true,
  "reason": "",
  "ignored_lines": [""],
  "transactions": [{
    "type": "IN|OUT",
    "amount": 0,
    "description": "",
    "category_hint": "",
    "date_iso": "",
    "date_source": "explicit|inferred|unknown",
    "confidence": 0,
    "raw_text": "",
    "needs_review": false,
    "warning": ""
  }]
}

OCR mentah:
$rawText
''';
        final response = await _postGenerateContent(
          model: model,
          contents: [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          generationConfig: _textStructuringGenerationConfig(),
        );

        if (response.statusCode == 429) {
          throw buildAiRateLimitExceptionFromResponse(response);
        }
        if (response.statusCode >= 400) {
          final detail = _extractErrorDetail(response.body);
          if (response.statusCode == 404) {
            lastError = Exception(
              '[Gemini] Model structuring OCR tidak ditemukan: $model. ${detail.isNotEmpty ? detail : ''}'
                  .trim(),
            );
            continue;
          }
          if (response.statusCode >= 500) {
            lastError = AiProviderTemporaryException(
              'Server AI sedang sibuk (${response.statusCode}).',
            );
            continue;
          }
          lastError = Exception(
            '[Gemini] Structuring OCR gagal (${response.statusCode}) di model $model. ${detail.isNotEmpty ? detail : ''}'
                .trim(),
          );
          continue;
        }

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final text = _extractJoinedText(body);
        if (text.trim().isNotEmpty) {
          onProviderEvent?.call(stage, 'ok', null);
          return text;
        }
        lastError = Exception('AI tidak mengembalikan data OCR terstruktur.');
        onProviderEvent?.call(stage, 'error', lastError.toString());
      } on AiRateLimitException {
        onProviderEvent?.call(stage, 'rate_limit', '429');
        rethrow;
      } on AiProviderTemporaryException catch (error) {
        lastError = error;
        onProviderEvent?.call(stage, 'temporary', error.toString());
      } on SocketException {
        onProviderEvent?.call(
          stage,
          'temporary',
          'Tidak ada koneksi internet.',
        );
        throw const AiProviderTemporaryException('Tidak ada koneksi internet.');
      } on TimeoutException {
        lastError = const AiProviderTemporaryException(
          'Permintaan OCR AI timeout. Coba lagi.',
        );
        onProviderEvent?.call(stage, 'temporary', lastError.toString());
      } on HttpException {
        lastError = const AiProviderTemporaryException(
          'Gagal menghubungi server AI.',
        );
        onProviderEvent?.call(stage, 'temporary', lastError.toString());
      } catch (error) {
        lastError = error;
        onProviderEvent?.call(stage, 'error', error.toString());
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw const AiProviderTemporaryException(
      'Gagal melakukan structuring OCR.',
    );
  }

  List<String> _textStructuringModelsFromEnvironment() {
    final parsed =
        _textStructuringModelChain
            .split(',')
            .map((entry) => entry.trim())
            .where((entry) => entry.isNotEmpty)
            .toList();
    if (parsed.isEmpty) {
      return const ['gemma-3-12b-it'];
    }
    return parsed;
  }

  Map<String, dynamic> _visionGenerationConfigForModel() {
    final normalized = _model.toLowerCase();
    final temperature = normalized.contains('flash-lite') ? 0.1 : 0.0;
    return {
      'temperature': temperature,
      'topP': 1,
      'candidateCount': 1,
      'maxOutputTokens': _maxVisionOutputTokens,
      'responseMimeType': 'text/plain',
    };
  }

  Map<String, dynamic> _textStructuringGenerationConfig() {
    return {
      'temperature': 0.0,
      'topP': 1,
      'candidateCount': 1,
      'maxOutputTokens': _maxStructuringOutputTokens,
      'responseMimeType': 'application/json',
      'responseSchema': {
        'type': 'OBJECT',
        'properties': {
          'summary': {
            'type': 'OBJECT',
            'properties': {
              'date_detected': {'type': 'STRING'},
              'notes_found': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'properties': {
                    'label': {'type': 'STRING'},
                    'value': {'type': 'STRING'},
                  },
                },
              },
            },
          },
          'is_transaction': {'type': 'BOOLEAN'},
          'reason': {'type': 'STRING'},
          'ignored_lines': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'transactions': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'type': {'type': 'STRING'},
                'amount': {'type': 'NUMBER'},
                'description': {'type': 'STRING'},
                'category_hint': {'type': 'STRING'},
                'date_iso': {'type': 'STRING'},
                'date_source': {'type': 'STRING'},
                'confidence': {'type': 'NUMBER'},
                'raw_text': {'type': 'STRING'},
                'needs_review': {'type': 'BOOLEAN'},
                'warning': {'type': 'STRING'},
              },
            },
          },
        },
        'required': ['is_transaction', 'reason', 'transactions'],
      },
    };
  }

  Future<http.Response> _postGenerateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    required Map<String, dynamic> generationConfig,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_apiKey',
    );
    try {
      return await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': contents,
              'generationConfig': generationConfig,
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
  }

  void _throwIfVisionResponseError(http.Response response) {
    if (response.statusCode == 429) {
      throw buildAiRateLimitExceptionFromResponse(response);
    }
    if (response.statusCode < 400) {
      return;
    }
    if (response.statusCode >= 500) {
      throw AiProviderTemporaryException(
        'Server AI sedang sibuk (${response.statusCode}).',
      );
    }
    final detail = _extractErrorDetail(response.body);
    switch (response.statusCode) {
      case 400:
        throw Exception(
          '[Gemini] Permintaan OCR ditolak (400). ${detail.isNotEmpty ? detail : 'Periksa format file (JPG/PNG/WEBP), ukuran gambar, atau konfigurasi model.'}',
        );
      case 401:
        throw Exception(
          '[Gemini] API key AI tidak valid atau belum benar. ${detail.isNotEmpty ? detail : ''}'
              .trim(),
        );
      case 403:
        throw Exception(
          '[Gemini] Akses OCR AI ditolak. ${detail.isNotEmpty ? detail : 'Periksa API key/kuota.'}',
        );
      case 404:
        throw Exception(
          '[Gemini] Model OCR AI tidak ditemukan. ${detail.isNotEmpty ? detail : ''}'
              .trim(),
        );
      default:
        throw Exception(
          '[Gemini] Permintaan OCR AI gagal (${response.statusCode}). ${detail.isNotEmpty ? detail : ''}'
              .trim(),
        );
    }
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
    if (start == -1) {
      throw Exception(
        'AI tidak mengembalikan format transaksi yang valid. Coba foto catatan transaksi yang lebih jelas.',
      );
    }
    if (end == -1 || end <= start) {
      throw Exception(
        'Respons OCR AI terpotong/tidak lengkap. Coba tekan "Coba Lagi".',
      );
    }

    final jsonText = raw.substring(start, end + 1);
    final decoded = _decodeJsonWithRepair(jsonText);
    if (decoded == null) {
      throw Exception(
        'Format JSON OCR AI tidak valid. Coba tekan "Coba Lagi".',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'AI mengembalikan data OCR yang tidak terbaca sistem. Coba foto ulang.',
      );
    }
    return decoded;
  }

  dynamic _decodeJsonWithRepair(String jsonText) {
    try {
      return jsonDecode(jsonText);
    } on FormatException {
      // Repair common model formatting glitches: smart quotes and trailing commas.
      var repaired =
          jsonText
              .replaceAll('\u201c', '"')
              .replaceAll('\u201d', '"')
              .replaceAll('\u2018', "'")
              .replaceAll('\u2019', "'")
              .replaceAll(RegExp(r',(\s*[}\]])'), r'$1')
              .trim();
      try {
        return jsonDecode(repaired);
      } on FormatException {
        return null;
      }
    }
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
