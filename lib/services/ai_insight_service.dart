import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AiInsightService {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );

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
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.25, 'maxOutputTokens': 300},
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

    final Map<String, dynamic> body = jsonDecode(response.body);
    final candidates = body['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('AI tidak mengembalikan saran.');
    }

    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    final text = parts != null && parts.isNotEmpty ? parts.first['text'] : null;
    if (text is! String || text.trim().isEmpty) {
      throw Exception('Jawaban AI kosong.');
    }

    return text.trim();
  }
}
