import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_import_draft.dart';
import 'ai_chatbot_memory_service.dart';
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
    this.actionDraft,
  });

  final String text;
  final String providerId;
  final bool fromCache;
  final int suggestedCooldownSeconds;
  final ChatImportDraft? actionDraft;
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
  final AiChatbotMemoryService _memoryService = AiChatbotMemoryService();

  Future<AiChatReply> askFinancialAssistant({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    List<AiChatMessage> history = const [],
  }) async {
    final safeQuestion = question.trim();
    final memory = await _memoryService.loadMemory();
    final memoryAction = _resolveMemoryAction(
      question: safeQuestion,
      memory: memory,
    );
    if (memoryAction != null) {
      return _applyMemoryAction(action: memoryAction, memory: memory);
    }
    if (_looksLikeImportAction(safeQuestion)) {
      final action = await _tryBuildImportDraftFromQuestion(
        question: safeQuestion,
        financeSnapshot: financeSnapshot,
      );
      if (action == null) {
        return const AiChatReply(
          text:
              'Format daftar transaksi belum jelas. Kirim ulang dengan format baris per transaksi, contoh: "Bolu coklat 2x 12000".',
          providerId: 'chat-action-intent',
          fromCache: false,
          suggestedCooldownSeconds: 1,
        );
      }
      return AiChatReply(
        text:
            'Draf transaksi berhasil disiapkan. Silakan review dulu sebelum disimpan.',
        providerId: action.providerId,
        fromCache: false,
        suggestedCooldownSeconds: 1,
        actionDraft: action.draft,
      );
    }

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
      question: safeQuestion,
      financeSnapshot: financeSnapshot,
      history: boundedHistory,
      memory: memory,
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
      question: safeQuestion,
      financeSnapshot: financeSnapshot,
      history: boundedHistory,
      memory: memory,
    );

    final askedCategories = _extractAskedCategories(
      question: safeQuestion,
      financeSnapshot: financeSnapshot,
    );

    final firstResponse = await _requestWithFallback(prompt);
    final firstParsed = _tryParseStructuredResponse(firstResponse.text);
    final firstIssue = _validateStructuredResponse(
      response: firstParsed,
      askedCategories: askedCategories,
    );

    _StructuredChatResponse? finalParsed = firstParsed;
    var providerId = firstResponse.providerId;
    if (firstIssue != null) {
      final retryPrompt = _buildStrictRetryPrompt(
        question: safeQuestion,
        financeSnapshot: financeSnapshot,
        history: boundedHistory,
        askedCategories: askedCategories,
        previousIssue: firstIssue,
        memory: memory,
      );
      final retryResponse = await _requestWithFallback(retryPrompt);
      providerId = retryResponse.providerId;
      final retryParsed = _tryParseStructuredResponse(retryResponse.text);
      final retryIssue = _validateStructuredResponse(
        response: retryParsed,
        askedCategories: askedCategories,
      );
      if (retryIssue == null && retryParsed != null) {
        finalParsed = retryParsed;
      } else {
        finalParsed = _buildLocalFallbackStructuredResponse(
          question: safeQuestion,
          financeSnapshot: financeSnapshot,
          askedCategories: askedCategories,
        );
        providerId = 'local-fallback';
      }
    }

    if (finalParsed == null) {
      throw const AiProviderTemporaryException('Jawaban AI kosong. Coba lagi.');
    }
    final cleaned = _renderStructuredResponse(finalParsed);
    if (cleaned.isEmpty) {
      throw const AiProviderTemporaryException('Jawaban AI kosong. Coba lagi.');
    }

    await _saveCache(fingerprint: fingerprint, text: cleaned);
    return AiChatReply(
      text: cleaned,
      providerId: providerId,
      fromCache: false,
      suggestedCooldownSeconds:
          providerId == 'cache'
              ? 1
              : providerId == 'groq'
              ? 3
              : providerId == 'local-fallback'
              ? 1
              : 4,
    );
  }

  String _buildBoundedPrompt({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    required List<AiChatMessage> history,
    required AiChatbotMemory memory,
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
    final categoryHints = _buildCategoryHints(financeSnapshot);
    final memoryText = _memoryService.renderMemoryForPrompt(memory);

    return '''
Kamu adalah asisten keuangan UMKM untuk toko kue.
Aturan keras:
- Jawaban hanya boleh terkait data keuangan toko pada konteks di bawah.
- Jika pertanyaan di luar konteks (cuaca, politik, umum), set status ke `outside_scope`.
- Jangan mengarang angka.
- Jawaban ringkas: maksimal 2 kalimat.
- Jika user menyebut kategori, gunakan nama kategori persis dari daftar kategori konteks.
- Data `top_product` dan `slow_product` adalah sampel, bukan seluruh katalog.
- Data `product_catalog` adalah stok saat ini. Jangan campur `stock_now` dengan `total_qty` penjualan.
- Data `income_category_30d` dan `expense_category_30d` adalah agregat kategori 30 hari.
- Jika data tidak cukup untuk jawaban pasti, set status ke `needs_data` dan sebut data tambahan yang dibutuhkan.
- Gunakan preferensi pengguna jika ada untuk sapaan awal (maksimal 1x), tanpa mengubah akurasi data.
- WAJIB output JSON valid saja, tanpa markdown, dengan schema tepat:
{"status":"ok|needs_data|outside_scope","jawaban":"","dasar_data":[{"source_type":"","kutipan":""}],"aksi_singkat":"","data_tambahan_dibutuhkan":""}
- Untuk status `ok`, `dasar_data` minimal 1 item dan `source_type` harus salah satu:
summary_30_days | daily_summary | income_category_30d | expense_category_30d | top_product | slow_product | product_catalog
- Untuk status `outside_scope`, `jawaban` harus persis:
"Saya hanya bisa membantu analisis data keuangan toko Anda."

Konteks data (agregat/transaksi ringkas):
$snapshotText

Daftar kategori terdeteksi:
$categoryHints

Preferensi pengguna (lokal):
$memoryText

Riwayat percakapan (terbatas):
$historyText

Pertanyaan user:
$safeQuestion
''';
  }

  String _buildStrictRetryPrompt({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    required List<AiChatMessage> history,
    required List<String> askedCategories,
    required String previousIssue,
    required AiChatbotMemory memory,
  }) {
    final historyText =
        history.isEmpty
            ? '- (kosong)'
            : history.map((m) => '- ${m.role}: ${m.text.trim()}').join('\n');
    final snapshotText =
        financeSnapshot.isEmpty
            ? '- Data belum tersedia.'
            : financeSnapshot
                .take(140)
                .map((row) => jsonEncode(row))
                .join('\n');
    final askedCategoryText =
        askedCategories.isEmpty
            ? '- (tidak spesifik kategori)'
            : askedCategories.join(', ');
    final categoryHints = _buildCategoryHints(financeSnapshot);
    final memoryText = _memoryService.renderMemoryForPrompt(memory);
    return '''
Ulangi. Respons sebelumnya tidak valid karena:
$previousIssue

WAJIB JSON valid saja, tanpa markdown.
Schema wajib:
{"status":"ok|needs_data|outside_scope","jawaban":"","dasar_data":[{"source_type":"","kutipan":""}],"aksi_singkat":"","data_tambahan_dibutuhkan":""}

Ketentuan wajib:
- status `outside_scope` => jawaban persis: "Saya hanya bisa membantu analisis data keuangan toko Anda."
- status `ok` => `dasar_data` minimal 1 item.
- Jika user tanya kategori spesifik, sebut kategori itu secara eksplisit di `jawaban` atau `dasar_data`.
- Jangan mengarang angka.

Kategori yang ditanya user:
$askedCategoryText

Daftar kategori konteks:
$categoryHints

Preferensi pengguna (lokal):
$memoryText

Konteks data:
$snapshotText

Riwayat percakapan:
$historyText

Pertanyaan user:
$question
''';
  }

  String _buildFingerprint({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    required List<AiChatMessage> history,
    required AiChatbotMemory memory,
  }) {
    final payload = jsonEncode({
      'q': question.trim(),
      'snapshot': financeSnapshot,
      'history':
          history
              .map((m) => {'role': m.role.trim(), 'text': m.text.trim()})
              .toList(),
      'memory': {
        'name': memory.preferredName,
        'salutation': memory.preferredSalutation,
        'tone': memory.tone,
      },
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  bool _looksLikeImportAction(String question) {
    final q = question.toLowerCase();
    return q.contains('tambahkan transaksi') ||
        q.contains('tambah transaksi') ||
        q.contains('import transaksi') ||
        q.contains('input transaksi ini');
  }

  Future<_ActionIntentResult?> _tryBuildImportDraftFromQuestion({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
  }) async {
    final prompt = _buildActionIntentPrompt(
      question: question,
      financeSnapshot: financeSnapshot,
    );
    final response = await _requestWithFallback(prompt);
    final draft = _tryParseActionDraftJson(response.text);
    if (draft == null || !draft.isValid) {
      return null;
    }
    return _ActionIntentResult(draft: draft, providerId: response.providerId);
  }

  String _buildActionIntentPrompt({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
  }) {
    final snapshotText = financeSnapshot
        .where((row) {
          final type = (row['type'] ?? '').toString();
          return type == 'income_category_30d' ||
              type == 'expense_category_30d';
        })
        .take(20)
        .map((row) => jsonEncode(row))
        .join('\n');
    final safeSnapshot =
        snapshotText.isEmpty ? '- kategori tidak tersedia' : snapshotText;

    return '''
Kamu mengubah teks chat menjadi draft transaksi untuk ditinjau user.
WAJIB output JSON valid saja, tanpa markdown, schema tepat:
{
  "intent":"import_transactions_draft",
  "source":"chat_manual_import",
  "is_partial_day":true/false,
  "missing_opening_block":true/false,
  "missing_closing_total":true/false,
  "inference_notes":["..."],
  "transactions":[
    {
      "type":"IN|OUT",
      "amount":12000,
      "description":"...",
      "category_hint":"...",
      "date_iso":"YYYY-MM-DD atau kosong",
      "date_source":"explicit|inferred|unknown",
      "needs_review":true/false,
      "warning":"..."
    }
  ],
  "notes_found":["..."],
  "ignored_lines":["..."],
  "confidence":0-100
}

Aturan:
- Maksimal 30 transaksi.
- Baris ambigu tetap masukkan sebagai transaksi dengan needs_review=true.
- Jika tanggal tidak jelas, date_iso = "".
- Jika tanggal ditebak dari konteks, set date_source="inferred" dan wajib needs_review=true.
- Gunakan date_source="explicit" hanya jika tanggal tertulis jelas di teks.
- Untuk nominal gabungan (contoh "10.000 + 5.000"), simpan ekspresinya di transaksi agar parser lokal bisa menghitungnya.
- Baris non-transaksi seperti "Total", "Uang Bersih", atau "Saldo" jangan masuk transactions; taruh ke notes_found/ignored_lines.
- Jangan mengarang nominal.
- Jika format input sangat buruk, tetap keluarkan JSON dengan transactions kosong.

Kategori referensi:
$safeSnapshot

Input user:
$question
''';
  }

  ChatImportDraft? _tryParseActionDraftJson(String rawText) {
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
    final draft = ChatImportDraft.fromJson(decoded);
    return draft.isValid ? draft : null;
  }

  _MemoryAction? _resolveMemoryAction({
    required String question,
    required AiChatbotMemory memory,
  }) {
    final q = question.trim().toLowerCase();
    if (q.isEmpty) {
      return null;
    }

    if (memory.hasPendingRename) {
      if (_isAffirmative(q)) {
        return const _MemoryAction(type: _MemoryActionType.confirmRename);
      }
      if (_isNegative(q)) {
        return const _MemoryAction(type: _MemoryActionType.cancelRename);
      }
    }

    if (q.contains('apa yang kamu ingat tentang saya') ||
        q.contains('apa yang kamu ingat') ||
        q.contains('kamu ingat apa tentang saya')) {
      return const _MemoryAction(type: _MemoryActionType.showMemory);
    }

    if (q.contains('lupakan saya') ||
        q.contains('hapus preferensi saya') ||
        q.contains('hapus memori saya')) {
      return const _MemoryAction(type: _MemoryActionType.clearMemory);
    }

    final tone = _extractTonePreference(q);
    if (tone != null) {
      return _MemoryAction(type: _MemoryActionType.setTone, value: tone);
    }

    final nameIntent = _extractNameIntent(question);
    if (nameIntent != null) {
      return _MemoryAction(
        type: _MemoryActionType.setName,
        value: nameIntent.name,
        aux: nameIntent.salutation,
      );
    }
    return null;
  }

  Future<AiChatReply> _applyMemoryAction({
    required _MemoryAction action,
    required AiChatbotMemory memory,
  }) async {
    if (action.type == _MemoryActionType.showMemory) {
      return AiChatReply(
        text: _memorySummaryText(memory),
        providerId: 'memory-local',
        fromCache: false,
        suggestedCooldownSeconds: 1,
      );
    }

    if (action.type == _MemoryActionType.clearMemory) {
      await _memoryService.clearMemory();
      return const AiChatReply(
        text: 'Baik, saya sudah melupakan preferensi Anda di perangkat ini.',
        providerId: 'memory-local',
        fromCache: false,
        suggestedCooldownSeconds: 1,
      );
    }

    if (action.type == _MemoryActionType.setTone) {
      final updated = memory.copyWith(tone: action.value ?? '');
      await _memoryService.saveMemory(updated);
      final toneLabel =
          (action.value ?? '').isEmpty ? 'default' : action.value!;
      return AiChatReply(
        text: 'Siap, gaya jawaban saya set ke "$toneLabel".',
        providerId: 'memory-local',
        fromCache: false,
        suggestedCooldownSeconds: 1,
      );
    }

    if (action.type == _MemoryActionType.setName) {
      final newName = (action.value ?? '').trim();
      if (newName.isEmpty) {
        return const AiChatReply(
          text: 'Nama belum terbaca jelas. Coba tulis: "nama saya ...".',
          providerId: 'memory-local',
          fromCache: false,
          suggestedCooldownSeconds: 1,
        );
      }
      final currentName = memory.preferredName.trim();
      final newSalutation = (action.aux ?? '').trim();
      if (currentName.isNotEmpty &&
          currentName.toLowerCase() != newName.toLowerCase()) {
        final pending = memory.copyWith(pendingName: newName);
        await _memoryService.saveMemory(pending);
        return AiChatReply(
          text:
              'Saat ini nama tersimpan "$currentName". Ubah ke "$newName"? Balas "ya" untuk konfirmasi atau "tidak" untuk batal.',
          providerId: 'memory-local',
          fromCache: false,
          suggestedCooldownSeconds: 1,
        );
      }

      final updated = memory.copyWith(
        preferredName: newName,
        preferredSalutation:
            newSalutation.isEmpty ? memory.preferredSalutation : newSalutation,
        pendingName: '',
      );
      await _memoryService.saveMemory(updated);
      final displayName = _buildDisplayName(
        name: updated.preferredName,
        salutation: updated.preferredSalutation,
      );
      return AiChatReply(
        text: 'Siap, saya akan menyapa Anda sebagai "$displayName".',
        providerId: 'memory-local',
        fromCache: false,
        suggestedCooldownSeconds: 1,
      );
    }

    if (action.type == _MemoryActionType.confirmRename) {
      final pendingName = memory.pendingName.trim();
      if (pendingName.isEmpty) {
        return const AiChatReply(
          text: 'Tidak ada perubahan nama yang menunggu konfirmasi.',
          providerId: 'memory-local',
          fromCache: false,
          suggestedCooldownSeconds: 1,
        );
      }
      final updated = memory.copyWith(
        preferredName: pendingName,
        pendingName: '',
      );
      await _memoryService.saveMemory(updated);
      final displayName = _buildDisplayName(
        name: updated.preferredName,
        salutation: updated.preferredSalutation,
      );
      return AiChatReply(
        text: 'Siap, nama panggilan diperbarui menjadi "$displayName".',
        providerId: 'memory-local',
        fromCache: false,
        suggestedCooldownSeconds: 1,
      );
    }

    if (action.type == _MemoryActionType.cancelRename) {
      if (!memory.hasPendingRename) {
        return const AiChatReply(
          text: 'Tidak ada perubahan nama yang menunggu konfirmasi.',
          providerId: 'memory-local',
          fromCache: false,
          suggestedCooldownSeconds: 1,
        );
      }
      await _memoryService.saveMemory(memory.copyWith(pendingName: ''));
      return const AiChatReply(
        text: 'Baik, perubahan nama dibatalkan.',
        providerId: 'memory-local',
        fromCache: false,
        suggestedCooldownSeconds: 1,
      );
    }

    return const AiChatReply(
      text: 'Perintah memori belum dikenali.',
      providerId: 'memory-local',
      fromCache: false,
      suggestedCooldownSeconds: 1,
    );
  }

  String _memorySummaryText(AiChatbotMemory memory) {
    final displayName = _buildDisplayName(
      name: memory.preferredName,
      salutation: memory.preferredSalutation,
    );
    final lines = <String>[
      displayName.isEmpty
          ? '- Nama/sapaan: belum diset'
          : '- Nama/sapaan: $displayName',
      memory.tone.isEmpty
          ? '- Gaya jawaban: default'
          : '- Gaya jawaban: ${memory.tone}',
    ];
    return 'Yang saya ingat saat ini:\n${lines.join('\n')}';
  }

  _NameIntent? _extractNameIntent(String question) {
    final regex = RegExp(
      r"\b(?:nama saya|panggil saya)\s+([A-Za-z][A-Za-z .'-]{1,40})",
      caseSensitive: false,
    );
    final match = regex.firstMatch(question);
    if (match == null) {
      return null;
    }
    final raw = (match.group(1) ?? '').split(RegExp(r'[.,!?]')).first;
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      return null;
    }

    final words = cleaned.split(' ');
    var salutation = '';
    final first = words.first.toLowerCase();
    if (first == 'pak' || first == 'bapak') {
      salutation = 'Pak';
      words.removeAt(0);
    } else if (first == 'bu' || first == 'ibu') {
      salutation = 'Bu';
      words.removeAt(0);
    } else if (first == 'kak') {
      salutation = 'Kak';
      words.removeAt(0);
    }

    final name = words.join(' ').trim();
    if (name.isEmpty) {
      return null;
    }
    return _NameIntent(name: _titleCase(name), salutation: salutation);
  }

  String? _extractTonePreference(String lowerQuestion) {
    if (!lowerQuestion.contains('gaya jawaban') &&
        !lowerQuestion.contains('tone')) {
      return null;
    }
    if (lowerQuestion.contains('ringkas')) {
      return 'ringkas';
    }
    if (lowerQuestion.contains('santai')) {
      return 'santai';
    }
    if (lowerQuestion.contains('formal')) {
      return 'formal';
    }
    if (lowerQuestion.contains('default')) {
      return '';
    }
    return null;
  }

  bool _isAffirmative(String lowerQuestion) {
    const yesWords = <String>{'ya', 'iya', 'yes', 'ok', 'oke', 'setuju'};
    return yesWords.contains(lowerQuestion.trim());
  }

  bool _isNegative(String lowerQuestion) {
    const noWords = <String>{'tidak', 'nggak', 'ga', 'enggak', 'batal', 'no'};
    return noWords.contains(lowerQuestion.trim());
  }

  String _buildDisplayName({required String name, required String salutation}) {
    final safeName = name.trim();
    final safeSalutation = salutation.trim();
    if (safeName.isEmpty) {
      return '';
    }
    if (safeSalutation.isEmpty) {
      return safeName;
    }
    return '$safeSalutation $safeName';
  }

  String _titleCase(String value) {
    final words =
        value.split(' ').where((word) => word.trim().isNotEmpty).map((word) {
          final lower = word.toLowerCase();
          if (lower.length <= 1) {
            return lower.toUpperCase();
          }
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        }).toList();
    return words.join(' ');
  }

  String _buildCategoryHints(List<Map<String, dynamic>> financeSnapshot) {
    final rows =
        financeSnapshot.where((row) {
          final type = (row['type'] ?? '').toString();
          return type == 'income_category_30d' ||
              type == 'expense_category_30d';
        }).toList();
    if (rows.isEmpty) {
      return '- (belum ada kategori 30 hari)';
    }
    final names =
        rows
            .map((row) => (row['category'] ?? '').toString().trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (names.isEmpty) {
      return '- (belum ada kategori 30 hari)';
    }
    return names.map((name) => '- $name').join('\n');
  }

  List<String> _extractAskedCategories({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
  }) {
    final q = question.toLowerCase();
    final categories =
        financeSnapshot
            .where((row) {
              final type = (row['type'] ?? '').toString();
              return type == 'income_category_30d' ||
                  type == 'expense_category_30d';
            })
            .map((row) => (row['category'] ?? '').toString().trim())
            .where((name) => name.isNotEmpty)
            .toSet();
    final asked = <String>[];
    for (final name in categories) {
      if (q.contains(name.toLowerCase())) {
        asked.add(name);
      }
    }
    return asked;
  }

  _StructuredChatResponse? _tryParseStructuredResponse(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final normalized =
        trimmed
            .replaceAll(RegExp(r'^```json\s*', caseSensitive: false), '')
            .replaceAll(RegExp(r'^```', caseSensitive: false), '')
            .replaceAll(RegExp(r'```$', caseSensitive: false), '')
            .trim();

    Map<String, dynamic>? decoded;
    try {
      final direct = jsonDecode(normalized);
      if (direct is Map<String, dynamic>) {
        decoded = direct;
      } else if (direct is Map) {
        decoded = Map<String, dynamic>.from(direct);
      }
    } catch (_) {
      final start = normalized.indexOf('{');
      final end = normalized.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final candidate = normalized.substring(start, end + 1);
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

    final status = (decoded['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'ok' && status != 'needs_data' && status != 'outside_scope') {
      return null;
    }
    final jawaban = (decoded['jawaban'] ?? '').toString().trim();
    if (jawaban.isEmpty) {
      return null;
    }

    final dasarRaw = decoded['dasar_data'];
    final dasarData = <_DataBasis>[];
    if (dasarRaw is List) {
      for (final item in dasarRaw) {
        final map =
            item is Map<String, dynamic>
                ? item
                : item is Map
                ? Map<String, dynamic>.from(item)
                : <String, dynamic>{};
        final sourceType = (map['source_type'] ?? '').toString().trim();
        final kutipan = (map['kutipan'] ?? '').toString().trim();
        if (sourceType.isEmpty || kutipan.isEmpty) {
          continue;
        }
        dasarData.add(_DataBasis(sourceType: sourceType, kutipan: kutipan));
      }
    }

    final aksiSingkat = (decoded['aksi_singkat'] ?? '').toString().trim();
    final dataTambahan =
        (decoded['data_tambahan_dibutuhkan'] ?? '').toString().trim();
    return _StructuredChatResponse(
      status: status,
      jawaban: jawaban,
      dasarData: dasarData,
      aksiSingkat: aksiSingkat,
      dataTambahanDibutuhkan: dataTambahan,
    );
  }

  String? _validateStructuredResponse({
    required _StructuredChatResponse? response,
    required List<String> askedCategories,
  }) {
    if (response == null) {
      return 'response bukan JSON terstruktur valid';
    }
    if (response.status == 'outside_scope' &&
        response.jawaban !=
            'Saya hanya bisa membantu analisis data keuangan toko Anda.') {
      return 'status outside_scope wajib pakai kalimat baku';
    }
    if (response.status == 'ok' && response.dasarData.isEmpty) {
      return 'status ok wajib menyertakan minimal 1 dasar_data';
    }
    if (response.status == 'needs_data' &&
        response.dataTambahanDibutuhkan.isEmpty) {
      return 'status needs_data wajib menyebut data_tambahan_dibutuhkan';
    }

    const allowedSourceTypes = <String>{
      'summary_30_days',
      'daily_summary',
      'income_category_30d',
      'expense_category_30d',
      'top_product',
      'slow_product',
      'product_catalog',
    };
    for (final item in response.dasarData) {
      if (!allowedSourceTypes.contains(item.sourceType)) {
        return 'source_type tidak valid: ${item.sourceType}';
      }
    }

    if (askedCategories.isNotEmpty && response.status == 'ok') {
      final combinedText =
          [
            response.jawaban,
            response.aksiSingkat,
            ...response.dasarData.map((d) => d.kutipan),
          ].join(' ').toLowerCase();
      final hasCategoryMention = askedCategories.any(
        (category) => combinedText.contains(category.toLowerCase()),
      );
      if (!hasCategoryMention) {
        return 'jawaban belum menyinggung kategori yang ditanyakan user';
      }
    }
    return null;
  }

  String _renderStructuredResponse(_StructuredChatResponse response) {
    if (response.status == 'outside_scope') {
      return response.jawaban;
    }
    final lines = <String>[response.jawaban];
    if (response.dasarData.isNotEmpty) {
      lines.add('Dasar data:');
      lines.addAll(
        response.dasarData.take(3).map((item) => '- ${item.kutipan}'),
      );
    }
    if (response.aksiSingkat.isNotEmpty) {
      lines.add('Aksi singkat: ${response.aksiSingkat}');
    }
    if (response.status == 'needs_data' &&
        response.dataTambahanDibutuhkan.isNotEmpty) {
      lines.add('Data tambahan dibutuhkan: ${response.dataTambahanDibutuhkan}');
    }
    return lines.join('\n').trim();
  }

  _StructuredChatResponse _buildLocalFallbackStructuredResponse({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    required List<String> askedCategories,
  }) {
    if (_looksOutsideScope(question)) {
      return const _StructuredChatResponse(
        status: 'outside_scope',
        jawaban: 'Saya hanya bisa membantu analisis data keuangan toko Anda.',
        dasarData: [],
        aksiSingkat: '',
        dataTambahanDibutuhkan: '',
      );
    }

    final summary = financeSnapshot.firstWhere(
      (row) => (row['type'] ?? '').toString() == 'summary_30_days',
      orElse:
          () => {
            'type': 'summary_30_days',
            'income': 0,
            'expense': 0,
            'net': 0,
          },
    );
    final income = _toInt(summary['income']);
    final expense = _toInt(summary['expense']);
    final net = _toInt(summary['net']);

    final incomeMap = _categoryAmountMap(
      financeSnapshot,
      'income_category_30d',
    );
    final expenseMap = _categoryAmountMap(
      financeSnapshot,
      'expense_category_30d',
    );

    if (askedCategories.isNotEmpty) {
      final category = askedCategories.first;
      final inAmount = incomeMap[category.toLowerCase()] ?? 0;
      final outAmount = expenseMap[category.toLowerCase()] ?? 0;
      if (inAmount == 0 && outAmount == 0) {
        return _StructuredChatResponse(
          status: 'needs_data',
          jawaban:
              'Data kategori $category belum cukup untuk dianalisis pasti.',
          dasarData: const [],
          aksiSingkat: '',
          dataTambahanDibutuhkan:
              'Butuh transaksi lebih lengkap untuk kategori $category dalam 30 hari.',
        );
      }
      return _StructuredChatResponse(
        status: 'ok',
        jawaban:
            'Kategori $category tercatat pemasukan Rp $inAmount dan pengeluaran Rp $outAmount dalam 30 hari.',
        dasarData: [
          _DataBasis(
            sourceType:
                inAmount >= outAmount
                    ? 'income_category_30d'
                    : 'expense_category_30d',
            kutipan:
                'Kategori $category: pemasukan Rp $inAmount, pengeluaran Rp $outAmount.',
          ),
          _DataBasis(
            sourceType: 'summary_30_days',
            kutipan:
                'Ringkasan 30 hari: pemasukan Rp $income, pengeluaran Rp $expense, selisih Rp $net.',
          ),
        ],
        aksiSingkat:
            outAmount > inAmount
                ? 'Evaluasi biaya kategori $category dan tetapkan batas belanja mingguan.'
                : 'Pertahankan performa kategori $category sambil kontrol margin.',
        dataTambahanDibutuhkan: '',
      );
    }

    return _StructuredChatResponse(
      status: 'ok',
      jawaban:
          'Dalam 30 hari, pemasukan Rp $income, pengeluaran Rp $expense, selisih Rp $net.',
      dasarData: [
        _DataBasis(
          sourceType: 'summary_30_days',
          kutipan:
              'Ringkasan 30 hari: pemasukan Rp $income, pengeluaran Rp $expense, selisih Rp $net.',
        ),
      ],
      aksiSingkat:
          net < 0
              ? 'Prioritaskan pengurangan biaya kategori terbesar minggu ini.'
              : 'Pertahankan tren positif dengan fokus stok produk paling laku.',
      dataTambahanDibutuhkan: '',
    );
  }

  bool _looksOutsideScope(String question) {
    final q = question.toLowerCase();
    const financeKeywords = <String>[
      'keuangan',
      'laba',
      'untung',
      'rugi',
      'pendapatan',
      'pemasukan',
      'pengeluaran',
      'biaya',
      'stok',
      'produk',
      'kategori',
      'kas',
      'penjualan',
      'transaksi',
      'omzet',
      'margin',
    ];
    return !financeKeywords.any(q.contains);
  }

  Map<String, int> _categoryAmountMap(
    List<Map<String, dynamic>> financeSnapshot,
    String type,
  ) {
    final map = <String, int>{};
    for (final row in financeSnapshot) {
      if ((row['type'] ?? '').toString() != type) {
        continue;
      }
      final category = (row['category'] ?? '').toString().trim().toLowerCase();
      if (category.isEmpty) {
        continue;
      }
      map[category] = _toInt(row['total_amount']);
    }
    return map;
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
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

class _DataBasis {
  const _DataBasis({required this.sourceType, required this.kutipan});

  final String sourceType;
  final String kutipan;
}

class _StructuredChatResponse {
  const _StructuredChatResponse({
    required this.status,
    required this.jawaban,
    required this.dasarData,
    required this.aksiSingkat,
    required this.dataTambahanDibutuhkan,
  });

  final String status;
  final String jawaban;
  final List<_DataBasis> dasarData;
  final String aksiSingkat;
  final String dataTambahanDibutuhkan;
}

enum _MemoryActionType {
  showMemory,
  clearMemory,
  setTone,
  setName,
  confirmRename,
  cancelRename,
}

class _MemoryAction {
  const _MemoryAction({required this.type, this.value, this.aux});

  final _MemoryActionType type;
  final String? value;
  final String? aux;
}

class _NameIntent {
  const _NameIntent({required this.name, required this.salutation});

  final String name;
  final String salutation;
}

class _ActionIntentResult {
  const _ActionIntentResult({required this.draft, required this.providerId});

  final ChatImportDraft draft;
  final String providerId;
}
