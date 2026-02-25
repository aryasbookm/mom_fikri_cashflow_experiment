import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_import_draft.dart';
import 'ai_chatbot_memory_service.dart';
import 'chat_intent_router.dart';
import 'ai_insight_service.dart';
import 'ai_providers/ai_vision_provider.dart';

class AiChatMessage {
  const AiChatMessage({
    required this.role,
    required this.text,
    this.providerId,
    this.confidenceLevel,
    this.confidenceReason,
    this.executionPath,
    this.executionReason,
  });

  final String role; // "user" | "assistant"
  final String text;
  final String? providerId;
  final String? confidenceLevel; // high | medium | low
  final String? confidenceReason;
  final String? executionPath; // local | local_ai | llm
  final String? executionReason;
}

class AiChatReply {
  const AiChatReply({
    required this.text,
    required this.providerId,
    required this.fromCache,
    required this.suggestedCooldownSeconds,
    this.actionDraft,
    this.confidenceLevel = 'medium',
    this.confidenceReason,
    this.executionPath,
    this.executionReason,
  });

  final String text;
  final String providerId;
  final bool fromCache;
  final int suggestedCooldownSeconds;
  final ChatImportDraft? actionDraft;
  final String confidenceLevel; // high | medium | low
  final String? confidenceReason;
  final String? executionPath; // local | local_ai | llm
  final String? executionReason;
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
  static const int _maxOutputTokens = 900;
  static const int _maxHistoryMessages = 8;
  static const int _maxProviderRetries = 2;
  static const double _aiIntentConfidenceThreshold = 0.65;
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const List<String> _clarificationOptions = <String>[
    'Cek stok',
    'Cek pemasukan/pengeluaran',
    'Input draf transaksi',
    'Analisis laporan',
  ];
  static const List<String> _hardIntentClarificationOptions = <String>[
    'Cek stok',
    'Cek pemasukan/pengeluaran',
    'Input draf transaksi',
  ];

  static const String _cacheKeyText = 'ai_chat_cache_text_v1';
  static const String _cacheKeyHash = 'ai_chat_cache_hash_v1';
  static const String _cacheKeyEpoch = 'ai_chat_cache_epoch_v1';
  final AiChatbotMemoryService _memoryService = AiChatbotMemoryService();
  final ChatIntentRouter _intentRouter = ChatIntentRouter();

  Future<AiChatReply> askFinancialAssistant({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    List<AiChatMessage> history = const [],
    String? providerOrderOverride,
  }) async {
    final safeQuestion = question.trim();
    if (safeQuestion.length > 3500) {
      return _finalizeConfidenceReply(
        const AiChatReply(
          text:
              'Pertanyaan terlalu panjang untuk diproses aman dalam satu kali kirim. Pecah jadi 2-3 pesan: (1) angka/fakta utama, (2) pertanyaan analisis, (3) saran yang diinginkan.',
          providerId: 'local-guard',
          fromCache: false,
          suggestedCooldownSeconds: 1,
          confidenceLevel: 'low',
          confidenceReason: 'Pertanyaan terlalu panjang dan berpotensi ambigu.',
        ),
      );
    }
    final memory = await _memoryService.loadMemory();
    final memoryAction = _resolveMemoryAction(
      question: safeQuestion,
      memory: memory,
    );
    if (memoryAction != null) {
      return _finalizeConfidenceReply(
        await _applyMemoryAction(action: memoryAction, memory: memory),
      );
    }

    final localIntent = _intentRouter.classify(safeQuestion);
    final localRoutedReply = await _routeIntentDecision(
      decision: localIntent,
      question: safeQuestion,
      financeSnapshot: financeSnapshot,
      providerOrderOverride: providerOrderOverride,
    );
    if (localRoutedReply != null) {
      return _finalizeConfidenceReply(localRoutedReply);
    }

    if (localIntent.type == ChatIntentType.unknown ||
        localIntent.type == ChatIntentType.ambiguous ||
        localIntent.type == ChatIntentType.outsideScope) {
      final normalizedQuestion = localIntent.normalizedQuestion;
      if (_looksHardIntentCandidate(normalizedQuestion)) {
        return _finalizeConfidenceReply(
          _buildClarificationReply(
            ChatIntentDecision(
              type: ChatIntentType.ambiguous,
              confidence: 0.4,
              normalizedQuestion: normalizedQuestion,
              reason: 'hard_intent_ambiguous_local_guard',
              clarificationOptions: _hardIntentClarificationOptions,
            ),
          ),
        );
      } else {
        final aiIntent = await _classifyIntentWithAi(
          question: safeQuestion,
          providerOrderOverride: providerOrderOverride,
        );
        if (aiIntent != null) {
          if (aiIntent.type == ChatIntentType.outsideScope) {
            return _finalizeConfidenceReply(_buildOutsideScopeReply());
          }
          final isLowConfidence =
              aiIntent.confidence < _aiIntentConfidenceThreshold;
          final isAmbiguous =
              aiIntent.type == ChatIntentType.ambiguous ||
              aiIntent.type == ChatIntentType.unknown;
          if (isLowConfidence || isAmbiguous) {
            return _finalizeConfidenceReply(_buildClarificationReply(aiIntent));
          }
          final aiRoutedReply = await _routeIntentDecision(
            decision: aiIntent,
            question: safeQuestion,
            financeSnapshot: financeSnapshot,
            providerOrderOverride: providerOrderOverride,
          );
          if (aiRoutedReply != null) {
            return _finalizeConfidenceReply(aiRoutedReply);
          }
        }
      }

      if (localIntent.type == ChatIntentType.outsideScope) {
        return _finalizeConfidenceReply(_buildOutsideScopeReply());
      }
      if (localIntent.type == ChatIntentType.unknown ||
          localIntent.type == ChatIntentType.ambiguous) {
        return _finalizeConfidenceReply(_buildClarificationReply(localIntent));
      }
    }

    if (_looksLikeImportAction(safeQuestion) ||
        _looksLikeTransactionListText(safeQuestion)) {
      final action = await _tryBuildImportDraftFromQuestion(
        question: safeQuestion,
        financeSnapshot: financeSnapshot,
        providerOrderOverride: providerOrderOverride,
      );
      if (action == null) {
        return _finalizeConfidenceReply(
          const AiChatReply(
            text:
                'Saya mendeteksi ini seperti daftar transaksi, tapi ada bagian yang belum cukup jelas untuk diproses aman (mis. nominal/format baris/tanggal). Coba kirim ulang dengan format 1 baris per transaksi, contoh: "Donat 20000" atau "Sosis 10000 + 5000". Jika tanggal tidak ada, saya akan pakai tanggal hari ini dan tandai untuk review.',
            providerId: 'chat-action-intent',
            fromCache: false,
            suggestedCooldownSeconds: 1,
            confidenceLevel: 'low',
            confidenceReason:
                'Format transaksi ambigu dan belum aman diproses.',
          ),
        );
      }
      return _finalizeConfidenceReply(
        AiChatReply(
          text:
              'Draf transaksi berhasil disiapkan. Silakan review dulu sebelum disimpan.',
          providerId: action.providerId,
          fromCache: false,
          suggestedCooldownSeconds: 1,
          actionDraft: action.draft,
          confidenceLevel: _confidenceForDraft(action.draft),
          confidenceReason: _confidenceReasonForDraft(action.draft),
        ),
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
    final detailedMode = _isDetailedAnalysisRequest(safeQuestion);

    final fingerprint = _buildFingerprint(
      question: safeQuestion,
      financeSnapshot: financeSnapshot,
      history: boundedHistory,
      memory: memory,
    );

    final cached = await _tryGetCached(fingerprint);
    if (cached != null) {
      return _finalizeConfidenceReply(
        AiChatReply(
          text: cached,
          providerId: 'cache',
          fromCache: true,
          suggestedCooldownSeconds: 1,
          confidenceLevel: 'medium',
          confidenceReason:
              'Jawaban diambil dari cache konteks data yang sama.',
        ),
      );
    }

    final prompt = _buildBoundedPrompt(
      question: localIntent.normalizedQuestion,
      financeSnapshot: financeSnapshot,
      history: boundedHistory,
      memory: memory,
      detailedMode: detailedMode,
    );

    final askedCategories = _extractAskedCategories(
      question: localIntent.normalizedQuestion,
      financeSnapshot: financeSnapshot,
    );

    final firstResponse = await _requestWithFallback(
      prompt,
      providerOrderOverride: providerOrderOverride,
    );
    final firstParsed = _tryParseStructuredResponse(firstResponse.text);
    final firstIssue = _validateStructuredResponse(
      response: firstParsed,
      askedCategories: askedCategories,
      detailedMode: detailedMode,
    );

    _StructuredChatResponse? finalParsed = firstParsed;
    var providerId = firstResponse.providerId;
    if (firstIssue != null) {
      final retryPrompt = _buildStrictRetryPrompt(
        question: localIntent.normalizedQuestion,
        financeSnapshot: financeSnapshot,
        history: boundedHistory,
        askedCategories: askedCategories,
        previousIssue: firstIssue,
        memory: memory,
        detailedMode: detailedMode,
      );
      final retryResponse = await _requestWithFallback(
        retryPrompt,
        providerOrderOverride: providerOrderOverride,
      );
      providerId = retryResponse.providerId;
      final retryParsed = _tryParseStructuredResponse(retryResponse.text);
      final retryIssue = _validateStructuredResponse(
        response: retryParsed,
        askedCategories: askedCategories,
        detailedMode: detailedMode,
      );
      if (retryIssue == null && retryParsed != null) {
        finalParsed = retryParsed;
      } else {
        finalParsed = _buildLocalFallbackStructuredResponse(
          question: safeQuestion,
          financeSnapshot: financeSnapshot,
          askedCategories: askedCategories,
          detailedMode: detailedMode,
        );
        providerId = 'local-fallback';
      }
    }

    if (finalParsed == null) {
      throw const AiProviderTemporaryException('Jawaban AI kosong. Coba lagi.');
    }
    final cleaned = _renderStructuredResponse(
      finalParsed,
      detailedMode: detailedMode,
      analyticalMode: _isAnalyticalQuestion(localIntent.normalizedQuestion),
    );
    if (cleaned.isEmpty) {
      throw const AiProviderTemporaryException('Jawaban AI kosong. Coba lagi.');
    }

    final confidenceLevel = _confidenceForProvider(
      providerId: providerId,
      response: finalParsed,
    );
    final confidenceReason = _confidenceReasonForProvider(
      providerId: providerId,
      response: finalParsed,
    );
    await _saveCache(fingerprint: fingerprint, text: cleaned);
    return _finalizeConfidenceReply(
      AiChatReply(
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
        confidenceLevel: confidenceLevel,
        confidenceReason: confidenceReason,
      ),
    );
  }

  Future<AiChatReply?> _routeIntentDecision({
    required ChatIntentDecision decision,
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    String? providerOrderOverride,
  }) async {
    final smartSearchReply = _resolveDeterministicSmartSearchReply(
      question: question,
      financeSnapshot: financeSnapshot,
    );
    if (smartSearchReply != null) {
      return smartSearchReply;
    }

    switch (decision.type) {
      case ChatIntentType.capabilityHelp:
        return _resolveInstantLocalReply(
          decision.normalizedQuestion,
          forceCapability: true,
        );
      case ChatIntentType.smallTalk:
        return _resolveInstantLocalReply(decision.normalizedQuestion);
      case ChatIntentType.stockQuery:
        return _resolveDeterministicStockRankingReply(
          question: decision.normalizedQuestion,
          financeSnapshot: financeSnapshot,
        );
      case ChatIntentType.dateQuery:
        return _resolveDeterministicDateQueryReply(
          question: question,
          financeSnapshot: financeSnapshot,
          providerOrderOverride: providerOrderOverride,
        );
      case ChatIntentType.importDraft:
        final action = await _tryBuildImportDraftFromQuestion(
          question: question,
          financeSnapshot: financeSnapshot,
          providerOrderOverride: providerOrderOverride,
        );
        if (action == null) {
          return const AiChatReply(
            text:
                'Saya mendeteksi ini seperti daftar transaksi, tapi ada bagian yang belum cukup jelas untuk diproses aman (mis. nominal/format baris/tanggal). Coba kirim ulang dengan format 1 baris per transaksi, contoh: "Donat 20000" atau "Sosis 10000 + 5000". Jika tanggal tidak ada, saya akan pakai tanggal hari ini dan tandai untuk review.',
            providerId: 'chat-action-intent',
            fromCache: false,
            suggestedCooldownSeconds: 1,
            confidenceLevel: 'low',
            confidenceReason:
                'Format transaksi ambigu dan belum aman diproses.',
          );
        }
        return AiChatReply(
          text:
              'Draf transaksi berhasil disiapkan. Silakan review dulu sebelum disimpan.',
          providerId: action.providerId,
          fromCache: false,
          suggestedCooldownSeconds: 1,
          actionDraft: action.draft,
          confidenceLevel: _confidenceForDraft(action.draft),
          confidenceReason: _confidenceReasonForDraft(action.draft),
        );
      case ChatIntentType.analysis:
      case ChatIntentType.outsideScope:
      case ChatIntentType.ambiguous:
      case ChatIntentType.unknown:
        return null;
    }
  }

  AiChatReply _buildClarificationReply(ChatIntentDecision decision) {
    final options =
        decision.clarificationOptions.isEmpty
            ? _clarificationOptions
            : decision.clarificationOptions;
    final lines = <String>[
      'Maksud Anda yang mana?',
      ...options.map((option) => '- $option'),
      'Balas salah satu opsi di atas agar saya proses dengan tepat.',
    ];
    return AiChatReply(
      text: lines.join('\n'),
      providerId: 'local-clarification',
      fromCache: false,
      suggestedCooldownSeconds: 1,
      confidenceLevel: 'medium',
      confidenceReason: 'Pertanyaan ambigu dan butuh klarifikasi intent.',
    );
  }

  AiChatReply _buildOutsideScopeReply() {
    return const AiChatReply(
      text: 'Saya hanya bisa membantu analisis data keuangan toko Anda.',
      providerId: 'local-scope-guard',
      fromCache: false,
      suggestedCooldownSeconds: 1,
      confidenceLevel: 'high',
      confidenceReason: 'Topik di luar cakupan asisten keuangan toko.',
    );
  }

  Future<ChatIntentDecision?> _classifyIntentWithAi({
    required String question,
    String? providerOrderOverride,
  }) async {
    final normalized = _intentRouter.normalize(question);
    if (normalized.isEmpty) {
      return null;
    }

    final prompt = _buildIntentClassifierPrompt(normalized);
    try {
      final response = await _requestWithFallback(
        prompt,
        providerOrderOverride: providerOrderOverride,
      );
      return _tryParseIntentClassifierDecision(
        rawText: response.text,
        normalizedQuestion: normalized,
      );
    } on AiRateLimitException {
      return null;
    } on AiProviderTemporaryException {
      return null;
    } catch (_) {
      return null;
    }
  }

  String _buildIntentClassifierPrompt(String question) {
    return '''
Anda adalah classifier intent untuk asisten keuangan toko.
Tugas Anda hanya klasifikasi soft-intent (bukan menghitung angka).

Pilih SATU intent dari daftar berikut:
- capability_help
- small_talk
- analysis
- outside_scope
- ambiguous
- unknown

WAJIB output JSON valid saja tanpa markdown:
{"intent":"...","confidence":0-100,"reason":"...","suggestions":["...","..."]}

Aturan:
- Jika user menyapa atau tes singkat => small_talk.
- Jika user tanya kemampuan bot/cara pakai => capability_help.
- Jika user minta insight/saran/analisis dari data toko => analysis.
- Jika topik jelas di luar keuangan toko => outside_scope.
- Jika user sebenarnya terlihat seperti perintah stok/tanggal/import transaksi, set `intent=ambiguous` dan beri `suggestions` kontekstual.
- Jika maksud belum jelas => ambiguous.
- confidence wajib angka 0..100.
- suggestions berisi 2-3 opsi singkat yang paling relevan (contoh: "Cek stok", "Cek pemasukan/pengeluaran", "Input draf transaksi").

Few-shot contoh:
Input: "siapa nama ku?"
Output: {"intent":"capability_help","confidence":86,"reason":"identity_question","suggestions":["Kemampuan bot","Lihat memori"]}
Input: "barang sisa berapa"
Output: {"intent":"ambiguous","confidence":52,"reason":"hard_intent_not_allowed_here","suggestions":["Cek stok","Cek pemasukan/pengeluaran"]}
Input: "kenapa bulan ini sepi"
Output: {"intent":"analysis","confidence":78,"reason":"analysis_request","suggestions":["Analisis laporan","Aksi prioritas"]}

Teks user:
$question
''';
  }

  ChatIntentDecision? _tryParseIntentClassifierDecision({
    required String rawText,
    required String normalizedQuestion,
  }) {
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

    final intentRaw =
        (decoded['intent'] ?? decoded['label'] ?? '').toString().trim();
    final intent = _parseSoftIntentType(intentRaw);
    if (intent == null) {
      return null;
    }

    final rawConfidence = decoded['confidence'];
    double confidence = 0.0;
    if (rawConfidence is num) {
      confidence = rawConfidence.toDouble();
    } else {
      confidence = double.tryParse(rawConfidence?.toString() ?? '') ?? 0.0;
    }
    if (confidence > 1.0) {
      confidence = confidence / 100.0;
    }
    confidence = confidence.clamp(0.0, 1.0);
    final reason =
        (decoded['reason'] ?? 'ai_intent_classifier').toString().trim();
    final clarifications = _extractAiClarificationOptions(decoded);
    return ChatIntentDecision(
      type: intent,
      confidence: confidence,
      normalizedQuestion: normalizedQuestion,
      reason: reason.isEmpty ? 'ai_intent_classifier' : reason,
      clarificationOptions: clarifications,
    );
  }

  ChatIntentType? _parseSoftIntentType(String raw) {
    final value = raw.trim().toLowerCase();
    switch (value) {
      case 'capability_help':
      case 'capabilityhelp':
      case 'help':
        return ChatIntentType.capabilityHelp;
      case 'small_talk':
      case 'smalltalk':
      case 'greeting':
        return ChatIntentType.smallTalk;
      case 'analysis':
      case 'insight':
      case 'analytical':
        return ChatIntentType.analysis;
      case 'outside_scope':
      case 'out_of_scope':
      case 'outside':
        return ChatIntentType.outsideScope;
      case 'ambiguous':
      case 'clarification':
        return ChatIntentType.ambiguous;
      case 'unknown':
        return ChatIntentType.unknown;
      default:
        return null;
    }
  }

  List<String> _extractAiClarificationOptions(Map<String, dynamic> decoded) {
    final raw =
        decoded['suggestions'] ?? decoded['options'] ?? decoded['candidates'];
    final normalized = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final text = item.toString().trim();
        if (text.isEmpty) {
          continue;
        }
        final mapped = _mapClarificationOption(text);
        if (mapped.isEmpty || normalized.contains(mapped)) {
          continue;
        }
        normalized.add(mapped);
        if (normalized.length >= 3) {
          break;
        }
      }
    }
    return normalized.isEmpty ? _clarificationOptions : normalized;
  }

  String _mapClarificationOption(String raw) {
    final q = raw.toLowerCase();
    if (q.contains('stok') || q.contains('stock')) {
      return 'Cek stok';
    }
    if (q.contains('pemasukan') ||
        q.contains('pengeluaran') ||
        q.contains('keuangan') ||
        q.contains('laporan harian')) {
      return 'Cek pemasukan/pengeluaran';
    }
    if (q.contains('draf') || q.contains('input') || q.contains('transaksi')) {
      return 'Input draf transaksi';
    }
    if (q.contains('analisis') ||
        q.contains('insight') ||
        q.contains('saran')) {
      return 'Analisis laporan';
    }
    if (q.contains('bantu') || q.contains('kemampuan') || q.contains('fitur')) {
      return 'Bantuan / kemampuan bot';
    }
    if (q.contains('memori') || q.contains('nama')) {
      return 'Lihat memori / nama tersimpan';
    }
    return raw.trim();
  }

  bool _looksHardIntentCandidate(String normalizedQuestion) {
    final q = normalizedQuestion.toLowerCase();
    if (_looksLikeImportAction(q) || _looksLikeTransactionListText(q)) {
      return true;
    }
    final stockSignals =
        q.contains('stok') ||
        q.contains('stock') ||
        q.contains('sisa') ||
        q.contains('produk aktif') ||
        q.contains('diarsipkan');
    final dateSignals =
        q.contains('hari ini') ||
        q.contains('kemarin') ||
        q.contains('hari lalu') ||
        q.contains('minggu') ||
        q.contains('bulan') ||
        RegExp(r'\b\d{1,2}\s+\d{1,2}\s+\d{2,4}\b').hasMatch(q) ||
        RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b').hasMatch(q) ||
        RegExp(r'\b\d{4}-\d{2}-\d{2}\b').hasMatch(q);
    return stockSignals || dateSignals;
  }

  AiChatReply? _resolveInstantLocalReply(
    String question, {
    bool forceCapability = false,
  }) {
    final q = question.trim().toLowerCase();
    if (q.isEmpty) {
      return null;
    }

    if (forceCapability || _isCapabilityHelpQuery(q)) {
      return const AiChatReply(
        text:
            'Saya Asisten Mom Fiqry.\n'
            'Saya bisa membantu:\n'
            '- Analisis data keuangan toko (30 hari).\n'
            '- Menjawab pertanyaan kategori pemasukan/pengeluaran.\n'
            '- Mengubah daftar chat menjadi draf transaksi untuk direview sebelum simpan.\n'
            'Batasan:\n'
            '- Tidak menjalankan aksi di luar data toko.\n'
            '- Tidak mengakses internet bebas.\n'
            '- Tidak menyimpan transaksi tanpa konfirmasi Anda.\n'
            'Contoh perintah:\n'
            '- "Bandingkan penghasilan hari ini dan kemarin."\n'
            '- "Sebutkan stok selain yang 0."\n'
            '- "Buat draf transaksi dari daftar berikut."',
        providerId: 'local-smalltalk',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'high',
        confidenceReason: 'Jawaban berasal dari capability lokal yang statis.',
      );
    }

    if (_isGreetingQuery(q)) {
      return const AiChatReply(
        text:
            'Halo, saya Asisten Mom Fiqry. Saya siap bantu analisis keuangan toko atau susun draf transaksi dari chat.',
        providerId: 'local-smalltalk',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'high',
        confidenceReason: 'Jawaban small-talk lokal deterministik.',
      );
    }

    if (_isClassicSmallTalkQuery(q)) {
      return const AiChatReply(
        text:
            'Kabar baik, terima kasih. Saya fokus membantu urusan keuangan toko. Kalau mau, kirim data transaksi atau pertanyaan analisis.',
        providerId: 'local-smalltalk',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'high',
        confidenceReason: 'Jawaban small-talk lokal deterministik.',
      );
    }

    return null;
  }

  AiChatReply? _resolveDeterministicStockRankingReply({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
  }) {
    final q = question.toLowerCase();
    final asksStock =
        q.contains('stok') || q.contains('stock') || q.contains('sisa');
    final asksProductStatus =
        q.contains('produk aktif') ||
        q.contains('aktif saja') ||
        q.contains('produk arsip') ||
        q.contains('produk diarsipkan') ||
        q.contains('produk yang diarsipkan') ||
        q.contains('produk nonaktif');
    final asksArchived =
        q.contains('arsip') ||
        q.contains('diarsipkan') ||
        q.contains('nonaktif');
    final asksActive =
        q.contains('aktif') &&
        !q.contains('nonaktif') &&
        !q.contains('arsip') &&
        !q.contains('diarsipkan');
    final asksOrder =
        q.contains('urut') ||
        q.contains('ranking') ||
        q.contains('tertinggi') ||
        q.contains('terendah');
    final asksListOnly =
        q.contains('stoknya berapa') ||
        q.contains('stok berapa') ||
        q.contains('sebutkan stok') ||
        q.contains('daftar stok') ||
        q.contains('stok selain') ||
        q.contains('stok di atas') ||
        q.contains('masih') ||
        q.contains('sisa') ||
        q.contains('cek');
    if (!(asksStock || asksProductStatus)) {
      return null;
    }

    final products =
        financeSnapshot
            .where(
              (row) =>
                  (row['type'] ?? '').toString().trim() == 'product_catalog',
            )
            .map((row) {
              final name = (row['name'] ?? '').toString().trim();
              final stock = _toInt(row['stock_now']);
              final isActive = _toBool(row['is_active'], defaultValue: true);
              if (name.isEmpty) {
                return null;
              }
              return <String, dynamic>{
                'name': name,
                'stock_now': stock,
                'is_active': isActive,
              };
            })
            .whereType<Map<String, dynamic>>()
            .toList();
    if (products.isEmpty) {
      return const AiChatReply(
        text:
            'Data stok produk belum tersedia di konteks chat saat ini. Coba refresh data dashboard lalu tanyakan lagi.',
        providerId: 'local-deterministic',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'medium',
        confidenceReason: 'Data stok belum tersedia di snapshot saat ini.',
      );
    }

    final hideZero =
        q.contains('tanpa') && q.contains('0') ||
        q.contains('selain') && q.contains('0') ||
        q.contains('di atas 0') ||
        q.contains('> 0') ||
        q.contains('bukan 0');
    var rows = List<Map<String, dynamic>>.from(products);
    if (asksProductStatus) {
      rows =
          asksArchived
              ? rows.where((row) => (row['is_active'] ?? true) != true).toList()
              : asksActive
              ? rows.where((row) => (row['is_active'] ?? true) == true).toList()
              : rows;
    }
    if (hideZero) {
      rows = rows.where((row) => _toInt(row['stock_now']) > 0).toList();
    }
    if (asksOrder) {
      rows.sort(
        (a, b) => _toInt(b['stock_now']).compareTo(_toInt(a['stock_now'])),
      );
    } else {
      rows.sort(
        (a, b) => (a['name'] ?? '').toString().compareTo(
          (b['name'] ?? '').toString(),
        ),
      );
    }
    if (rows.isEmpty) {
      return const AiChatReply(
        text:
            'Semua stok saat ini bernilai 0, jadi tidak ada item untuk ditampilkan.',
        providerId: 'local-deterministic',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'high',
        confidenceReason: 'Jawaban dihitung langsung dari katalog stok lokal.',
      );
    }

    final limit = _extractTopLimit(q) ?? 10;
    final topRows = rows.take(limit).toList();
    final statusTitle =
        asksProductStatus
            ? asksArchived
                ? 'Produk arsip saat ini:'
                : asksActive
                ? 'Produk aktif saat ini:'
                : 'Daftar produk saat ini:'
            : null;
    final lines = <String>[
      statusTitle ??
          (asksOrder
              ? 'Stok saat ini (urut tertinggi ke terendah${hideZero ? ', tanpa stok 0' : ''}):'
              : 'Produk dengan stok ${hideZero ? 'lebih dari 0' : 'saat ini'}:'),
      ...topRows.map((row) {
        if (asksProductStatus && !asksStock && !asksListOnly) {
          return '- ${row['name']}';
        }
        return '- ${row['name']}: ${NumberFormat('#,##0', 'id_ID').format(_toInt(row['stock_now']))}';
      }),
    ];
    return AiChatReply(
      text: lines.join('\n'),
      providerId: 'local-deterministic',
      fromCache: false,
      suggestedCooldownSeconds: 1,
      confidenceLevel: 'high',
      confidenceReason: 'Urutan stok dihitung deterministik dari data katalog.',
      executionPath: 'local',
      executionReason: 'Query stok dieksekusi langsung dari snapshot lokal.',
    );
  }

  AiChatReply? _resolveDeterministicSmartSearchReply({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
  }) {
    final q = question.toLowerCase().trim();
    final asksSearch =
        q.contains('cari ') ||
        q.startsWith('cari') ||
        q.contains('temukan') ||
        q.contains('filter') ||
        q.contains('riwayat') ||
        q.contains('tampilkan');
    if (!asksSearch) {
      return null;
    }

    final minAmount = _extractMinimumAmount(q);
    final asksIncome = q.contains('pemasukan') || q.contains('penghasilan');
    final asksExpense = q.contains('pengeluaran') || q.contains('biaya');
    final asksCategory = q.contains('kategori');
    final asksProduct = q.contains('produk') || q.contains('stok');
    final asksDate = q.contains('tanggal') || q.contains('hari');

    var rows = List<Map<String, dynamic>>.from(financeSnapshot);
    if (asksCategory && (asksIncome || asksExpense)) {
      rows =
          rows.where((row) {
            final type = (row['type'] ?? '').toString();
            if (asksIncome && !asksExpense) {
              return type == 'income_category_30d';
            }
            if (asksExpense && !asksIncome) {
              return type == 'expense_category_30d';
            }
            return type == 'income_category_30d' ||
                type == 'expense_category_30d';
          }).toList();
      if (minAmount != null) {
        rows =
            rows
                .where((row) => _toInt(row['total_amount']) >= minAmount)
                .toList();
      }
      rows.sort(
        (a, b) =>
            _toInt(b['total_amount']).compareTo(_toInt(a['total_amount'])),
      );
      final limited = rows.take(8).toList();
      if (limited.isEmpty) {
        return const AiChatReply(
          text:
              'Tidak ada kategori yang cocok dengan filter pencarian Anda pada data 30 hari ini.',
          providerId: 'local-deterministic',
          fromCache: false,
          suggestedCooldownSeconds: 1,
          confidenceLevel: 'high',
          confidenceReason:
              'Filter kategori dihitung deterministik dari snapshot.',
          executionPath: 'local',
          executionReason:
              'Pencarian kategori dieksekusi langsung dari snapshot lokal.',
        );
      }
      final lines = limited
          .map((row) {
            final label = (row['category'] ?? '-').toString();
            final amount = NumberFormat(
              '#,##0',
              'id_ID',
            ).format(_toInt(row['total_amount']));
            final side =
                (row['type'] ?? '').toString() == 'income_category_30d'
                    ? 'IN'
                    : 'OUT';
            return '- [$side] $label: Rp $amount';
          })
          .join('\n');
      return AiChatReply(
        text: 'Hasil pencarian kategori:\n$lines',
        providerId: 'local-deterministic',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'high',
        confidenceReason:
            'Filter kategori dihitung deterministik dari snapshot.',
        executionPath: 'local',
        executionReason:
            'Pencarian kategori dieksekusi langsung dari snapshot lokal.',
      );
    }

    if (asksProduct) {
      rows =
          rows
              .where(
                (row) => (row['type'] ?? '').toString() == 'product_catalog',
              )
              .toList();
      if (minAmount != null) {
        rows =
            rows.where((row) => _toInt(row['stock_now']) >= minAmount).toList();
      }
      final limited = rows.take(10).toList();
      if (limited.isEmpty) {
        return const AiChatReply(
          text: 'Tidak ada produk yang cocok dengan filter pencarian tersebut.',
          providerId: 'local-deterministic',
          fromCache: false,
          suggestedCooldownSeconds: 1,
          confidenceLevel: 'high',
          confidenceReason:
              'Filter produk dihitung deterministik dari snapshot.',
          executionPath: 'local',
          executionReason:
              'Pencarian produk dieksekusi langsung dari snapshot lokal.',
        );
      }
      final lines = limited
          .map((row) {
            final name = (row['name'] ?? '-').toString();
            final stock = _toInt(row['stock_now']);
            return '- $name: stok $stock';
          })
          .join('\n');
      return AiChatReply(
        text: 'Hasil pencarian produk:\n$lines',
        providerId: 'local-deterministic',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'high',
        confidenceReason: 'Filter produk dihitung deterministik dari snapshot.',
        executionPath: 'local',
        executionReason:
            'Pencarian produk dieksekusi langsung dari snapshot lokal.',
      );
    }

    if (asksDate) {
      rows =
          rows
              .where((row) => (row['type'] ?? '').toString() == 'daily_summary')
              .toList();
      rows.sort(
        (a, b) => (b['date'] ?? '').toString().compareTo(
          (a['date'] ?? '').toString(),
        ),
      );
      final limited = rows.take(7).toList();
      if (limited.isEmpty) {
        return null;
      }
      final lines = limited
          .map((row) {
            final date = (row['date'] ?? '-').toString();
            final income = NumberFormat(
              '#,##0',
              'id_ID',
            ).format(_toInt(row['income']));
            final expense = NumberFormat(
              '#,##0',
              'id_ID',
            ).format(_toInt(row['expense']));
            return '- $date | IN Rp $income | OUT Rp $expense';
          })
          .join('\n');
      return AiChatReply(
        text: 'Riwayat harian terbaru:\n$lines',
        providerId: 'local-deterministic',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'high',
        confidenceReason: 'Data harian diambil deterministik dari snapshot.',
        executionPath: 'local',
        executionReason:
            'Pencarian riwayat harian dieksekusi dari snapshot lokal.',
      );
    }

    return null;
  }

  int? _extractMinimumAmount(String q) {
    final match = RegExp(
      r'(?:di atas|lebih dari|minimal|>=?)\s*(\d{1,3}(?:[.,]\d{3})+|\d+)\s*(ribu|rb|juta|jt)?',
    ).firstMatch(q);
    if (match == null) {
      return null;
    }
    final numberText = (match.group(1) ?? '').replaceAll(RegExp(r'[.,]'), '');
    final base = int.tryParse(numberText);
    if (base == null) {
      return null;
    }
    final unit = (match.group(2) ?? '').trim();
    if (unit == 'ribu' || unit == 'rb') {
      return base * 1000;
    }
    if (unit == 'juta' || unit == 'jt') {
      return base * 1000000;
    }
    return base;
  }

  int? _extractTopLimit(String q) {
    final topMatch = RegExp(r'\btop\s+(\d{1,2})\b').firstMatch(q);
    if (topMatch != null) {
      final parsed = int.tryParse(topMatch.group(1)!);
      if (parsed != null && parsed > 0) {
        return parsed.clamp(1, 50);
      }
    }
    final firstNum = RegExp(r'\b(\d{1,2})\b').firstMatch(q);
    if (firstNum != null) {
      final parsed = int.tryParse(firstNum.group(1)!);
      if (parsed != null && parsed > 0 && parsed <= 50) {
        return parsed;
      }
    }
    return null;
  }

  String _confidenceForDraft(ChatImportDraft draft) {
    final inferredCount =
        draft.transactions
            .where((item) => item.dateSource == 'inferred')
            .length;
    final needsReviewCount =
        draft.transactions.where((item) => item.needsReview).length;
    if (needsReviewCount > 0 || inferredCount > 0) {
      return 'medium';
    }
    return 'high';
  }

  String _confidenceReasonForDraft(ChatImportDraft draft) {
    final inferredCount =
        draft.transactions
            .where((item) => item.dateSource == 'inferred')
            .length;
    final needsReviewCount =
        draft.transactions.where((item) => item.needsReview).length;
    if (needsReviewCount > 0 || inferredCount > 0) {
      return 'Draf mengandung item review/inferensi tanggal.';
    }
    return 'Draf terbaca jelas dan tidak ada item review.';
  }

  String _confidenceForProvider({
    required String providerId,
    required _StructuredChatResponse response,
  }) {
    if (providerId == 'local-deterministic') {
      return 'high';
    }
    if (providerId == 'local-fallback') {
      return 'low';
    }
    if (providerId == 'groq' ||
        providerId == 'gemini' ||
        providerId == 'cache') {
      if (response.status == 'needs_data') {
        return 'medium';
      }
      return 'high';
    }
    return 'medium';
  }

  String _confidenceReasonForProvider({
    required String providerId,
    required _StructuredChatResponse response,
  }) {
    if (providerId == 'local-deterministic') {
      return 'Jawaban dihitung langsung dari data lokal secara deterministik.';
    }
    if (providerId == 'local-fallback') {
      return 'Provider utama gagal format/grounding, memakai fallback lokal.';
    }
    if (providerId == 'cache') {
      return 'Jawaban berasal dari cache snapshot data yang sama.';
    }
    if (response.status == 'needs_data') {
      return 'Data belum lengkap untuk jawaban yang sepenuhnya pasti.';
    }
    return 'Jawaban berasal dari provider AI dengan validasi struktur lokal.';
  }

  AiChatReply _finalizeConfidenceReply(AiChatReply reply) {
    var normalizedConfidence = reply.confidenceLevel.trim().toLowerCase();
    if (normalizedConfidence != 'high' &&
        normalizedConfidence != 'medium' &&
        normalizedConfidence != 'low') {
      normalizedConfidence = 'medium';
    }
    if ((reply.providerId == 'local-smalltalk' ||
            reply.providerId == 'memory-local') &&
        normalizedConfidence != 'high') {
      normalizedConfidence = 'high';
    }
    final normalizedPath =
        (reply.executionPath ?? _inferExecutionPath(reply.providerId)).trim();
    final finalPath =
        normalizedPath.isEmpty
            ? _inferExecutionPath(reply.providerId)
            : normalizedPath;
    final finalReason =
        (reply.executionReason ?? '').trim().isEmpty
            ? _inferExecutionReason(
              providerId: reply.providerId,
              path: finalPath,
            )
            : reply.executionReason;
    if (normalizedConfidence == reply.confidenceLevel &&
        finalPath == (reply.executionPath ?? '') &&
        finalReason == reply.executionReason) {
      return reply;
    }
    return AiChatReply(
      text: reply.text,
      providerId: reply.providerId,
      fromCache: reply.fromCache,
      suggestedCooldownSeconds: reply.suggestedCooldownSeconds,
      actionDraft: reply.actionDraft,
      confidenceLevel: normalizedConfidence,
      confidenceReason: reply.confidenceReason,
      executionPath: finalPath,
      executionReason: finalReason,
    );
  }

  String _inferExecutionPath(String providerId) {
    if (providerId == 'groq' ||
        providerId == 'gemini' ||
        providerId == 'cache') {
      return 'llm';
    }
    if (providerId == 'local-deterministic' ||
        providerId == 'local-smalltalk' ||
        providerId == 'memory-local' ||
        providerId == 'local-scope-guard' ||
        providerId == 'local-clarification' ||
        providerId == 'local-fallback') {
      return 'local';
    }
    return 'local';
  }

  String _inferExecutionReason({
    required String providerId,
    required String path,
  }) {
    if (path == 'llm') {
      return 'Jawaban utama dirender oleh provider AI dengan validasi lokal.';
    }
    if (providerId == 'local-fallback') {
      return 'Jawaban fallback lokal karena format/grounding provider utama tidak valid.';
    }
    return 'Jawaban dirender deterministik oleh engine lokal.';
  }

  Future<AiChatReply?> _resolveDeterministicDateQueryReply({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    String? providerOrderOverride,
  }) async {
    final q = question.toLowerCase().trim();
    final dailyRows =
        financeSnapshot
            .where((row) => (row['type'] ?? '').toString() == 'daily_summary')
            .toList();
    if (dailyRows.isEmpty) {
      return const AiChatReply(
        text:
            'Data harian belum tersedia, jadi saya belum bisa hitung tanggal yang diminta secara pasti. Pastikan transaksi harian sudah tercatat.',
        providerId: 'local-deterministic',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'medium',
        confidenceReason: 'Snapshot belum memiliki data daily_summary.',
      );
    }

    final now = DateTime.now();
    final resolved =
        _tryResolveDateQueryLocal(q, now) ??
        await _tryResolveDateQueryWithAi(
          question: question,
          now: now,
          providerOrderOverride: providerOrderOverride,
        );
    if (resolved == null) {
      return null;
    }

    final metric = _resolveDateMetric(q);
    final metricLabel = _metricLabel(metric);
    final executionPath = resolved.source == 'ai' ? 'local_ai' : 'local';
    final executionReason =
        resolved.source == 'ai'
            ? 'Tanggal dinormalisasi oleh AI, lalu perhitungan nominal dieksekusi lokal.'
            : 'Tanggal dan nominal diproses deterministik oleh engine lokal.';
    final dailyMap = <String, Map<String, dynamic>>{};
    for (final row in dailyRows) {
      final key = (row['date'] ?? '').toString().trim();
      if (key.isNotEmpty) {
        dailyMap[key] = row;
      }
    }

    String formatCurrency(int value) =>
        'Rp ${NumberFormat('#,##0', 'id_ID').format(value)}';

    final primary = resolved.primary;
    final primaryValue = _sumMetricInRange(dailyMap, metric, primary);
    if (resolved.compare == null) {
      if (primaryValue == null) {
        return AiChatReply(
          text:
              'Data $metricLabel untuk ${primary.label.toLowerCase()} belum tersedia.',
          providerId: 'local-deterministic',
          fromCache: false,
          suggestedCooldownSeconds: 1,
          confidenceLevel: 'medium',
          confidenceReason:
              'Data harian pada tanggal yang diminta belum tersedia.',
          executionPath: executionPath,
          executionReason: executionReason,
        );
      }
      return AiChatReply(
        text:
            '$metricLabel ${primary.label.toLowerCase()}: ${formatCurrency(primaryValue)}.',
        providerId: 'local-deterministic',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'high',
        confidenceReason:
            'Nilai dihitung deterministik dari daily_summary (${resolved.source}).',
        executionPath: executionPath,
        executionReason: executionReason,
      );
    }

    final compare = resolved.compare!;
    final compareValue = _sumMetricInRange(dailyMap, metric, compare);
    if (primaryValue == null || compareValue == null) {
      return AiChatReply(
        text:
            'Saya butuh data harian lengkap untuk membandingkan $metricLabel ${primary.label.toLowerCase()} vs ${compare.label.toLowerCase()}. '
            'Data tersedia: ${primary.label.toLowerCase()}=${primaryValue != null ? formatCurrency(primaryValue) : '-'}, '
            '${compare.label.toLowerCase()}=${compareValue != null ? formatCurrency(compareValue) : '-'}.',
        providerId: 'local-deterministic',
        fromCache: false,
        suggestedCooldownSeconds: 1,
        confidenceLevel: 'medium',
        confidenceReason: 'Sebagian data tanggal pembanding belum tersedia.',
        executionPath: executionPath,
        executionReason: executionReason,
      );
    }

    final delta = primaryValue - compareValue;
    final trend =
        delta > 0
            ? 'naik'
            : delta < 0
            ? 'turun'
            : 'stabil';
    final deltaAbs = NumberFormat('#,##0', 'id_ID').format(delta.abs());
    return AiChatReply(
      text:
          '$metricLabel ${primary.label}: ${formatCurrency(primaryValue)}\n'
          '$metricLabel ${compare.label}: ${formatCurrency(compareValue)}\n'
          'Perbandingan: $trend sebesar Rp $deltaAbs.',
      providerId: 'local-deterministic',
      fromCache: false,
      suggestedCooldownSeconds: 1,
      confidenceLevel: 'high',
      confidenceReason:
          'Komparasi dihitung deterministik dari daily_summary (${resolved.source}).',
      executionPath: executionPath,
      executionReason: executionReason,
    );
  }

  int? _sumMetricInRange(
    Map<String, Map<String, dynamic>> dailyMap,
    _DateMetric metric,
    _DateRangeWindow range,
  ) {
    var hasAny = false;
    var sum = 0;
    for (
      var date = range.start;
      !date.isAfter(range.end);
      date = date.add(const Duration(days: 1))
    ) {
      final key = DateFormat('yyyy-MM-dd').format(date);
      final value = _extractMetricValue(dailyMap[key], metric);
      if (value != null) {
        hasAny = true;
        sum += value;
      }
    }
    if (!hasAny) {
      return null;
    }
    return sum;
  }

  _ResolvedDateQuery? _tryResolveDateQueryLocal(String q, DateTime now) {
    final hasCompare =
        q.contains('banding') ||
        q.contains('compare') ||
        q.contains('perbandingan') ||
        q.contains(' vs ') ||
        q.contains(' dengan ');

    final explicitRange = _tryParseExplicitRange(q, now);
    if (explicitRange != null) {
      return _ResolvedDateQuery(primary: explicitRange, source: 'local');
    }

    if (hasCompare) {
      final today = _singleDayRange(now, 'Hari ini (${_formatDateId(now)})');
      final yesterday = _singleDayRange(
        now.subtract(const Duration(days: 1)),
        'Kemarin (${_formatDateId(now.subtract(const Duration(days: 1)))})',
      );
      final nDaysAgo = _extractNDaysAgoRange(q, now);
      final weekThis = _weekRange(now, labelPrefix: 'Minggu ini');
      final weekLast = _weekRange(
        now.subtract(const Duration(days: 7)),
        labelPrefix: 'Minggu lalu',
      );
      final monthThis = _monthRange(now, labelPrefix: 'Bulan ini');
      final monthLast = _monthRange(
        DateTime(now.year, now.month - 1, 15),
        labelPrefix: 'Bulan lalu',
      );

      if (nDaysAgo != null && q.contains('kemarin')) {
        return _ResolvedDateQuery(
          primary: nDaysAgo,
          compare: yesterday,
          source: 'local',
        );
      }
      if (q.contains('hari ini') && q.contains('kemarin')) {
        return _ResolvedDateQuery(
          primary: today,
          compare: yesterday,
          source: 'local',
        );
      }
      if (q.contains('minggu lalu') && q.contains('minggu ini')) {
        return _ResolvedDateQuery(
          primary: weekLast,
          compare: weekThis,
          source: 'local',
        );
      }
      if (q.contains('bulan lalu') && q.contains('bulan ini')) {
        return _ResolvedDateQuery(
          primary: monthLast,
          compare: monthThis,
          source: 'local',
        );
      }
    }

    if (q.contains('hari ini')) {
      return _ResolvedDateQuery(
        primary: _singleDayRange(now, 'Hari ini (${_formatDateId(now)})'),
        source: 'local',
      );
    }
    if (q.contains('kemarin')) {
      final day = now.subtract(const Duration(days: 1));
      return _ResolvedDateQuery(
        primary: _singleDayRange(day, 'Kemarin (${_formatDateId(day)})'),
        source: 'local',
      );
    }
    final nDaysAgo = _extractNDaysAgoRange(q, now);
    if (nDaysAgo != null) {
      return _ResolvedDateQuery(primary: nDaysAgo, source: 'local');
    }
    if (q.contains('7 hari terakhir')) {
      return _ResolvedDateQuery(
        primary: _rollingRange(now, days: 7, labelPrefix: '7 hari terakhir'),
        source: 'local',
      );
    }
    if (q.contains('30 hari terakhir')) {
      return _ResolvedDateQuery(
        primary: _rollingRange(now, days: 30, labelPrefix: '30 hari terakhir'),
        source: 'local',
      );
    }
    if (q.contains('minggu ini')) {
      return _ResolvedDateQuery(
        primary: _weekRange(now, labelPrefix: 'Minggu ini'),
        source: 'local',
      );
    }
    if (q.contains('minggu lalu')) {
      return _ResolvedDateQuery(
        primary: _weekRange(
          now.subtract(const Duration(days: 7)),
          labelPrefix: 'Minggu lalu',
        ),
        source: 'local',
      );
    }
    if (q.contains('bulan ini')) {
      return _ResolvedDateQuery(
        primary: _monthRange(now, labelPrefix: 'Bulan ini'),
        source: 'local',
      );
    }
    if (q.contains('bulan lalu')) {
      return _ResolvedDateQuery(
        primary: _monthRange(
          DateTime(now.year, now.month - 1, 15),
          labelPrefix: 'Bulan lalu',
        ),
        source: 'local',
      );
    }

    final explicitSingle = _tryParseSingleExplicitDate(q, now);
    if (explicitSingle != null) {
      return _ResolvedDateQuery(primary: explicitSingle, source: 'local');
    }
    return null;
  }

  Future<_ResolvedDateQuery?> _tryResolveDateQueryWithAi({
    required String question,
    required DateTime now,
    String? providerOrderOverride,
  }) async {
    final prompt = _buildDateNormalizerPrompt(question, now);
    try {
      final response = await _requestWithFallback(
        prompt,
        providerOrderOverride: providerOrderOverride,
      );
      return _tryParseDateNormalizerResponse(response.text);
    } on AiRateLimitException {
      return null;
    } on AiProviderTemporaryException {
      return null;
    } catch (_) {
      return null;
    }
  }

  String _buildDateNormalizerPrompt(String question, DateTime now) {
    final today = DateFormat('yyyy-MM-dd').format(now);
    return '''
Anda adalah normalizer tanggal untuk asisten keuangan toko.
Hari ini: $today.
Tugas Anda hanya menormalkan referensi waktu ke ISO date/range. Jangan hitung uang.

WAJIB output JSON valid saja:
{
  "mode":"single|range|compare|unknown",
  "primary_start":"YYYY-MM-DD atau kosong",
  "primary_end":"YYYY-MM-DD atau kosong",
  "compare_start":"YYYY-MM-DD atau kosong",
  "compare_end":"YYYY-MM-DD atau kosong",
  "label_primary":"...",
  "label_compare":"..."
}

Aturan:
- Jika tidak yakin, mode=unknown.
- Untuk frasa komparasi, gunakan mode=compare.
- Untuk tanggal tunggal, start=end.
- Jangan menambahkan penjelasan apapun di luar JSON.

Teks user:
$question
''';
  }

  _ResolvedDateQuery? _tryParseDateNormalizerResponse(String rawText) {
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
        try {
          final loose = jsonDecode(trimmed.substring(start, end + 1));
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

    final mode = (decoded['mode'] ?? '').toString().trim().toLowerCase();
    if (mode == 'unknown' || mode.isEmpty) {
      return null;
    }
    final primary = _buildRangeWindowFromIso(
      startIso: (decoded['primary_start'] ?? '').toString(),
      endIso: (decoded['primary_end'] ?? '').toString(),
      label: (decoded['label_primary'] ?? 'Rentang utama').toString().trim(),
    );
    if (primary == null) {
      return null;
    }
    if (mode == 'single' || mode == 'range') {
      return _ResolvedDateQuery(primary: primary, source: 'ai-normalizer');
    }
    if (mode == 'compare') {
      final compare = _buildRangeWindowFromIso(
        startIso: (decoded['compare_start'] ?? '').toString(),
        endIso: (decoded['compare_end'] ?? '').toString(),
        label:
            (decoded['label_compare'] ?? 'Rentang pembanding')
                .toString()
                .trim(),
      );
      if (compare == null) {
        return null;
      }
      return _ResolvedDateQuery(
        primary: primary,
        compare: compare,
        source: 'ai-normalizer',
      );
    }
    return null;
  }

  _DateRangeWindow? _buildRangeWindowFromIso({
    required String startIso,
    required String endIso,
    required String label,
  }) {
    final start = _tryParseIsoDate(startIso);
    final end = _tryParseIsoDate(endIso);
    if (start == null || end == null) {
      return null;
    }
    final safeStart = _startOfDay(start);
    final safeEnd = _startOfDay(end);
    final actualStart = safeStart.isBefore(safeEnd) ? safeStart : safeEnd;
    final actualEnd = safeStart.isBefore(safeEnd) ? safeEnd : safeStart;
    return _DateRangeWindow(
      start: actualStart,
      end: actualEnd,
      label:
          label.isEmpty
              ? '${_formatDateId(actualStart)}-${_formatDateId(actualEnd)}'
              : label,
    );
  }

  _DateRangeWindow? _extractNDaysAgoRange(String q, DateTime now) {
    final match = RegExp(r'\b(\d{1,4})\s+hari\s+lalu\b').firstMatch(q);
    if (match == null) {
      return null;
    }
    final days = int.tryParse(match.group(1) ?? '');
    if (days == null || days < 1 || days > 3650) {
      return null;
    }
    final day = now.subtract(Duration(days: days));
    return _singleDayRange(day, '$days hari lalu (${_formatDateId(day)})');
  }

  _DateRangeWindow? _tryParseSingleExplicitDate(String q, DateTime now) {
    final isoMatch = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b').firstMatch(q);
    if (isoMatch != null) {
      final date = _tryParseIsoDate(isoMatch.group(1)!);
      if (date != null) {
        return _singleDayRange(date, 'Tanggal ${_formatDateId(date)}');
      }
    }
    final dmyMatch = RegExp(
      r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b',
    ).firstMatch(q);
    if (dmyMatch != null) {
      final day = int.tryParse(dmyMatch.group(1)!);
      final month = int.tryParse(dmyMatch.group(2)!);
      final yearRaw = int.tryParse(dmyMatch.group(3)!);
      if (day != null && month != null && yearRaw != null) {
        final year = yearRaw < 100 ? 2000 + yearRaw : yearRaw;
        final date = _tryBuildSafeDate(year, month, day);
        if (date != null) {
          return _singleDayRange(date, 'Tanggal ${_formatDateId(date)}');
        }
      }
    }
    final monthNameMatch = RegExp(
      r'\b(\d{1,2})\s+(jan|feb|mar|apr|mei|jun|jul|agu|agt|sep|okt|nov|des|januari|februari|maret|april|juni|juli|agustus|september|oktober|november|desember)(?:\s+(\d{4}))?\b',
    ).firstMatch(q);
    if (monthNameMatch != null) {
      final day = int.tryParse(monthNameMatch.group(1)!);
      final month = _monthTokenToInt(monthNameMatch.group(2)!);
      final year = int.tryParse(monthNameMatch.group(3) ?? '') ?? now.year;
      if (day != null && month != null) {
        final date = _tryBuildSafeDate(year, month, day);
        if (date != null) {
          return _singleDayRange(date, 'Tanggal ${_formatDateId(date)}');
        }
      }
    }
    return null;
  }

  _DateRangeWindow? _tryParseExplicitRange(String q, DateTime now) {
    final rangeMatch = RegExp(
      r'\b(?:dari|antara)\s+(.+?)\s+(?:sampai|hingga|sd|dan)\s+(.+)$',
    ).firstMatch(q);
    if (rangeMatch == null) {
      return null;
    }
    final start = _tryParseExplicitDateToken(rangeMatch.group(1) ?? '', now);
    final end = _tryParseExplicitDateToken(rangeMatch.group(2) ?? '', now);
    if (start == null || end == null) {
      return null;
    }
    final safeStart = _startOfDay(start);
    final safeEnd = _startOfDay(end);
    final actualStart = safeStart.isBefore(safeEnd) ? safeStart : safeEnd;
    final actualEnd = safeStart.isBefore(safeEnd) ? safeEnd : safeStart;
    return _DateRangeWindow(
      start: actualStart,
      end: actualEnd,
      label: '${_formatDateId(actualStart)} s.d. ${_formatDateId(actualEnd)}',
    );
  }

  DateTime? _tryParseExplicitDateToken(String value, DateTime now) {
    final normalized = value.toLowerCase().trim();
    final asSingle = _tryParseSingleExplicitDate(normalized, now);
    if (asSingle != null) {
      return asSingle.start;
    }
    return null;
  }

  _DateRangeWindow _singleDayRange(DateTime day, String label) {
    final safe = _startOfDay(day);
    return _DateRangeWindow(start: safe, end: safe, label: label);
  }

  _DateRangeWindow _rollingRange(
    DateTime now, {
    required int days,
    required String labelPrefix,
  }) {
    final end = _startOfDay(now);
    final start = _startOfDay(now.subtract(Duration(days: days - 1)));
    return _DateRangeWindow(
      start: start,
      end: end,
      label: '$labelPrefix (${_formatDateId(start)}-${_formatDateId(end)})',
    );
  }

  _DateRangeWindow _weekRange(DateTime pivot, {required String labelPrefix}) {
    final safe = _startOfDay(pivot);
    final start = safe.subtract(Duration(days: safe.weekday - DateTime.monday));
    final end = start.add(const Duration(days: 6));
    return _DateRangeWindow(
      start: start,
      end: end,
      label: '$labelPrefix (${_formatDateId(start)}-${_formatDateId(end)})',
    );
  }

  _DateRangeWindow _monthRange(DateTime pivot, {required String labelPrefix}) {
    final start = DateTime(pivot.year, pivot.month, 1);
    final end = DateTime(pivot.year, pivot.month + 1, 0);
    return _DateRangeWindow(
      start: _startOfDay(start),
      end: _startOfDay(end),
      label: '$labelPrefix (${_formatDateId(start)}-${_formatDateId(end)})',
    );
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime? _tryParseIsoDate(String value) {
    final raw = value.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      return null;
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return null;
    }
    return _startOfDay(parsed);
  }

  DateTime? _tryBuildSafeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return _startOfDay(date);
  }

  int? _monthTokenToInt(String token) {
    switch (token.toLowerCase()) {
      case 'jan':
      case 'januari':
        return 1;
      case 'feb':
      case 'februari':
        return 2;
      case 'mar':
      case 'maret':
        return 3;
      case 'apr':
      case 'april':
        return 4;
      case 'mei':
        return 5;
      case 'jun':
      case 'juni':
        return 6;
      case 'jul':
      case 'juli':
        return 7;
      case 'agu':
      case 'agt':
      case 'agustus':
        return 8;
      case 'sep':
      case 'september':
        return 9;
      case 'okt':
      case 'oktober':
        return 10;
      case 'nov':
      case 'november':
        return 11;
      case 'des':
      case 'desember':
        return 12;
      default:
        return null;
    }
  }

  String _formatDateId(DateTime date) => DateFormat('d MMM yyyy').format(date);

  _DateMetric _resolveDateMetric(String q) {
    if (q.contains('pengeluaran') ||
        q.contains('biaya') ||
        q.contains('expense')) {
      return _DateMetric.expense;
    }
    if (q.contains('laba') ||
        q.contains('selisih') ||
        q.contains('untung') ||
        q.contains('net')) {
      return _DateMetric.net;
    }
    return _DateMetric.income;
  }

  String _metricLabel(_DateMetric metric) {
    switch (metric) {
      case _DateMetric.expense:
        return 'Pengeluaran';
      case _DateMetric.net:
        return 'Selisih';
      case _DateMetric.income:
        return 'Penghasilan';
    }
  }

  int? _extractMetricValue(Map<String, dynamic>? row, _DateMetric metric) {
    if (row == null) {
      return null;
    }
    final income = _toInt(row['income']);
    final expense = _toInt(row['expense']);
    switch (metric) {
      case _DateMetric.expense:
        return expense;
      case _DateMetric.net:
        return income - expense;
      case _DateMetric.income:
        return income;
    }
  }

  bool _isCapabilityHelpQuery(String q) {
    return q.contains('kamu bisa apa') ||
        q.contains('siapa nama mu') ||
        q.contains('siapa namamu') ||
        q.contains('siapa nama kamu') ||
        q.contains('deskripsikan diri') ||
        q.contains('bisa apa saja') ||
        q.contains('fitur kamu') ||
        q.contains('bantuan') ||
        q.contains('help') ||
        q.contains('cara pakai');
  }

  bool _isAnalyticalQuestion(String question) {
    final q = question.toLowerCase();
    const analyticalKeywords = <String>[
      'analisis',
      'banding',
      'penghasilan',
      'pemasukan',
      'pengeluaran',
      'laba',
      'selisih',
      'stok',
      'kategori',
      'omzet',
      'margin',
      'hari ini',
      'kemarin',
      '30 hari',
      'produk',
      'prioritas',
      'rekomendasi',
      'strategi',
    ];
    return analyticalKeywords.any(q.contains);
  }

  bool _isGreetingQuery(String q) {
    final normalized = q.trim();
    const greetings = <String>{
      'halo',
      'hai',
      'hi',
      'tes',
      'test',
      'pagi',
      'siang',
      'sore',
      'malam',
      'selamat pagi',
      'selamat siang',
      'selamat sore',
      'selamat malam',
    };
    if (greetings.contains(normalized)) {
      return true;
    }
    if (RegExp(r'^(halo|hai|hi|tes|test)\b').hasMatch(normalized)) {
      return true;
    }
    if (RegExp(r'^selamat (pagi|siang|sore|malam)\b').hasMatch(normalized)) {
      return true;
    }
    return false;
  }

  bool _isClassicSmallTalkQuery(String q) {
    final normalized = q.trim();
    const smallTalks = <String>{
      'apa kabar',
      'gimana kabar',
      'terima kasih',
      'makasih',
    };
    if (smallTalks.contains(normalized)) {
      return true;
    }
    return RegExp(
      r'^(apa kabar|gimana kabar|terima kasih|makasih)\b',
    ).hasMatch(normalized);
  }

  String _buildBoundedPrompt({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    required List<AiChatMessage> history,
    required AiChatbotMemory memory,
    required bool detailedMode,
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

    final verbosityRule =
        detailedMode
            ? '- MODE DETAIL aktif: jawab lebih mendalam dengan 4-8 poin/bagian yang tetap spesifik ke data.'
            : '- Jawaban ringkas: maksimal 2 kalimat.';

    return '''
Kamu adalah asisten keuangan UMKM untuk toko kue.
Aturan keras:
- Jawaban hanya boleh terkait data keuangan toko pada konteks di bawah.
- Jika pertanyaan di luar konteks (cuaca, politik, umum), set status ke `outside_scope`.
- Jangan mengarang angka.
$verbosityRule
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
    required bool detailedMode,
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
    final detailRule =
        detailedMode
            ? '- MODE DETAIL aktif: berikan jawaban mendalam (4-8 poin) berbasis data.'
            : '- Jawaban tetap ringkas dan tepat sasaran.';
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
$detailRule

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

  bool _looksLikeTransactionListText(String question) {
    final lines =
        question
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
    if (lines.length < 3) {
      return false;
    }
    var lineWithAmount = 0;
    var listLike = 0;
    for (final line in lines) {
      if (RegExp(r'\d[\d\.,]*').hasMatch(line)) {
        lineWithAmount += 1;
      }
      if (RegExp(r'^[-*•]|\b(in|out)\b', caseSensitive: false).hasMatch(line)) {
        listLike += 1;
      }
    }
    return lineWithAmount >= 3 || (lineWithAmount >= 2 && listLike >= 1);
  }

  bool _isDetailedAnalysisRequest(String question) {
    final q = question.toLowerCase();
    const detailKeywords = <String>[
      'analisis',
      'bandingkan',
      'bandingin',
      'saran',
      'strategi',
      'detail',
      'mendalam',
      'kenapa',
      'apa penyebab',
      'hari ini',
      'kemarin',
    ];
    final hitCount = detailKeywords.where(q.contains).length;
    return hitCount >= 2;
  }

  Future<_ActionIntentResult?> _tryBuildImportDraftFromQuestion({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    String? providerOrderOverride,
  }) async {
    final prompt = _buildActionIntentPrompt(
      question: question,
      financeSnapshot: financeSnapshot,
    );
    final response = await _requestWithFallback(
      prompt,
      providerOrderOverride: providerOrderOverride,
    );
    final draft = _tryParseActionDraftJson(response.text);
    if (draft == null || !draft.isValid) {
      return null;
    }
    final importHash =
        sha256.convert(utf8.encode(question.trim().toLowerCase())).toString();
    final enriched = draft.copyWith(importHash: importHash);
    return _ActionIntentResult(
      draft: enriched,
      providerId: response.providerId,
    );
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
        q.contains('kamu ingat apa tentang saya') ||
        q.contains('siapa nama ku') ||
        q.contains('siapa namaku') ||
        q.contains('apakah kau memiliki memori') ||
        q.contains('apakah kamu memiliki memori') ||
        q.contains('kamu punya memori')) {
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
      r"\b(?:nama saya|nama ku|namaku|panggil saya)\s+([A-Za-z][A-Za-z .'-]{1,40})",
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
    required bool detailedMode,
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
    if (detailedMode &&
        response.status == 'ok' &&
        response.jawaban.trim().length < 120) {
      return 'mode detail aktif tetapi jawaban terlalu singkat';
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

  String _renderStructuredResponse(
    _StructuredChatResponse response, {
    required bool detailedMode,
    required bool analyticalMode,
  }) {
    if (response.status == 'outside_scope') {
      return response.jawaban;
    }
    final lines = <String>[response.jawaban];
    if (analyticalMode && response.dasarData.isNotEmpty) {
      lines.add('Dasar data:');
      lines.addAll(
        response.dasarData.take(3).map((item) => '- ${item.kutipan}'),
      );
    }
    if (analyticalMode && response.aksiSingkat.isNotEmpty) {
      lines.add('Aksi singkat: ${response.aksiSingkat}');
    }
    if (response.status == 'needs_data' &&
        response.dataTambahanDibutuhkan.isNotEmpty) {
      lines.add('Data tambahan dibutuhkan: ${response.dataTambahanDibutuhkan}');
    }
    if (detailedMode && response.status == 'ok') {
      lines.add(
        'Jika Anda mau, saya bisa lanjutkan analisis lebih rinci per kategori/hari secara bertahap.',
      );
    }
    return lines.join('\n').trim();
  }

  _StructuredChatResponse _buildLocalFallbackStructuredResponse({
    required String question,
    required List<Map<String, dynamic>> financeSnapshot,
    required List<String> askedCategories,
    required bool detailedMode,
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
            detailedMode
                ? 'Analisis kategori $category (30 hari): pemasukan Rp $inAmount dan pengeluaran Rp $outAmount. Selisih kategori ini adalah Rp ${inAmount - outAmount}. Fokus utama: ${outAmount > inAmount ? 'tekan komponen biaya dominan di kategori ini' : 'pertahankan performa kategori sambil jaga margin'} dan validasi tren harian untuk mencegah penurunan mendadak.'
                : 'Kategori $category tercatat pemasukan Rp $inAmount dan pengeluaran Rp $outAmount dalam 30 hari.',
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
          detailedMode
              ? 'Ringkasan 30 hari: pemasukan Rp $income, pengeluaran Rp $expense, selisih Rp $net. Interpretasi cepat: ${net < 0 ? 'arus kas negatif menandakan biaya lebih cepat tumbuh dari pemasukan' : 'arus kas positif menandakan operasi relatif sehat'}. Langkah analitis berikutnya: bandingkan hari ini vs kemarin, lalu pecah biaya per kategori terbesar untuk cari sumber deviasi.'
              : 'Dalam 30 hari, pemasukan Rp $income, pengeluaran Rp $expense, selisih Rp $net.',
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

  bool _toBool(dynamic value, {required bool defaultValue}) {
    if (value == null) {
      return defaultValue;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final lowered = value.toString().trim().toLowerCase();
    if (lowered.isEmpty) {
      return defaultValue;
    }
    return lowered == 'true' || lowered == '1' || lowered == 'yes';
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

  Future<_ChatProviderResponse> _requestWithFallback(
    String prompt, {
    String? providerOrderOverride,
  }) async {
    final order =
        (providerOrderOverride ?? '').trim().isNotEmpty
            ? providerOrderOverride!.trim()
            : String.fromEnvironment(
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
        final text = await _requestProviderWithRetry(
          providerId,
          prompt,
          hasFallbackProvider: hasNext,
        );
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
    String prompt, {
    required bool hasFallbackProvider,
  }) async {
    Object? lastError;
    final maxAttempts = hasFallbackProvider ? 1 : _maxProviderRetries;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (providerId == 'groq') {
          return await _requestGroq(prompt);
        }
        return await _requestGemini(prompt);
      } on AiRateLimitException catch (error) {
        lastError = error;
        if (error.isDailyLimit || attempt >= maxAttempts) {
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
        if (attempt >= maxAttempts || hasFallbackProvider) {
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
    if (model.startsWith('models/')) {
      throw const AiProviderTemporaryException(
        'GEMINI_CHAT_MODEL tidak boleh diawali "models/". Gunakan nama pendek model, contoh: gemma-3-12b-it.',
      );
    }
    if (model == 'gemma-3-12b') {
      throw const AiProviderTemporaryException(
        'Model gemma-3-12b tidak ditemukan untuk chat. Gunakan gemma-3-12b-it.',
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
          .timeout(const Duration(seconds: 10));
    } on SocketException {
      throw const AiProviderTemporaryException('Tidak ada koneksi internet.');
    } on http.ClientException catch (error) {
      final raw = error.message.trim();
      throw AiProviderTemporaryException(
        raw.isEmpty
            ? 'Koneksi ke Gemini chat terputus. Sistem akan mencoba provider lain.'
            : 'Koneksi ke Gemini chat terputus: $raw',
      );
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
      if (response.statusCode == 404) {
        throw AiProviderTemporaryException(
          'Model Gemini chat ($_geminiModel) tidak tersedia (404). Sistem akan mencoba provider lain.',
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiProviderTemporaryException(
          'Akses Gemini chat gagal (401/403). Sistem akan mencoba provider lain.',
        );
      }
      throw AiProviderTemporaryException(
        'Permintaan Gemini chat gagal (${response.statusCode}). Sistem akan mencoba provider lain.',
      );
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
          .timeout(const Duration(seconds: 10));
    } on SocketException {
      throw const AiProviderTemporaryException('Tidak ada koneksi internet.');
    } on http.ClientException catch (error) {
      final raw = error.message.trim();
      throw AiProviderTemporaryException(
        raw.isEmpty
            ? 'Koneksi ke Groq chat terputus. Sistem akan mencoba provider lain.'
            : 'Koneksi ke Groq chat terputus: $raw',
      );
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

class _DateRangeWindow {
  const _DateRangeWindow({
    required this.start,
    required this.end,
    required this.label,
  });

  final DateTime start;
  final DateTime end;
  final String label;
}

class _ResolvedDateQuery {
  const _ResolvedDateQuery({
    required this.primary,
    required this.source,
    this.compare,
  });

  final _DateRangeWindow primary;
  final _DateRangeWindow? compare;
  final String source;
}

enum _DateMetric { income, expense, net }
