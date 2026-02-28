import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../models/chat_import_draft.dart';
import '../screens/history_screen.dart';
import '../screens/ocr_assist_screen.dart';
import '../services/ai_chatbot_service.dart';
import '../services/ai_insight_service.dart';

class AiChatbotScreen extends StatefulWidget {
  const AiChatbotScreen({
    super.key,
    required this.financeSnapshot,
    this.initialQuestion,
    this.initialDraft,
    this.initialDraftAuditText,
  });

  final List<Map<String, dynamic>> financeSnapshot;
  final String? initialQuestion;
  final ChatImportDraft? initialDraft;
  final String? initialDraftAuditText;

  @override
  State<AiChatbotScreen> createState() => _AiChatbotScreenState();
}

class _DraftDescriptionUpdate {
  const _DraftDescriptionUpdate({
    required this.sourceHint,
    required this.newDescription,
  });

  final String sourceHint;
  final String newDescription;
}

class _AiChatbotScreenState extends State<AiChatbotScreen> {
  final AiChatbotService _chatbotService = AiChatbotService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AiChatMessage> _messages = [];
  ChatImportDraft? _pendingDraft;
  int? _pendingDraftMessageIndex;

  bool _isLoading = false;
  int _cooldownSeconds = 0;
  bool _initialQuestionHandled = false;
  bool _initialDraftHandled = false;
  String? _pendingInitialQuestion;
  int? _pendingDraftCreatedAtEpochMs;
  String _chatProviderPriority = 'groq_first';
  bool _showTechnicalMeta = false;
  final Map<int, int> _assistantFeedback = <int, int>{}; // -1 | 1
  Set<String> _escalationPhrases = <String>{};
  Timer? _cooldownTimer;
  static const List<String> _quickQuestions = [
    'Kamu bisa apa?',
    'Apa 2 aksi prioritas minggu ini?',
    'Kenapa laba turun di 30 hari terakhir?',
    'Produk mana yang perlu dipromosikan dulu?',
    'Bagaimana menekan pengeluaran bahan baku?',
  ];
  static const String _chatStoreKey = 'ai_chat_history_v1';
  static const String _chatSnapshotKey = 'ai_chat_snapshot_hash_v1';
  static const String _chatSavedAtKey = 'ai_chat_saved_at_v1';
  static const String _chatProviderPriorityKey = 'ai_chat_provider_priority_v1';
  static const String _chatShowTechnicalMetaKey =
      'ai_chat_show_technical_meta_v1';
  static const String _chatPendingDraftKey = 'ai_chat_pending_draft_v1';
  static const String _chatPendingDraftMetaKey =
      'ai_chat_pending_draft_meta_v1';
  static const String _chatPendingDraftSnapshotKey =
      'ai_chat_pending_draft_snapshot_v1';

  @override
  void initState() {
    super.initState();
    _loadChatSettings();
    _loadPersistedChat();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChatSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved =
        (prefs.getString(_chatProviderPriorityKey) ?? 'groq_first').trim();
    final normalized = saved == 'gemini_first' ? 'gemini_first' : 'groq_first';
    final escalationRaw =
        await DatabaseHelper.instance.getChatPreferAiPhrases();
    final showTechnicalMeta = prefs.getBool(_chatShowTechnicalMetaKey) ?? false;
    if (!mounted) {
      return;
    }
    setState(() {
      _chatProviderPriority = normalized;
      _escalationPhrases = escalationRaw;
      _showTechnicalMeta = showTechnicalMeta;
    });
  }

  Future<void> _setChatProviderPriority(String value) async {
    final normalized = value == 'gemini_first' ? 'gemini_first' : 'groq_first';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatProviderPriorityKey, normalized);
    if (!mounted) {
      return;
    }
    setState(() {
      _chatProviderPriority = normalized;
    });
  }

  Future<void> _toggleTechnicalMeta() async {
    final next = !_showTechnicalMeta;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chatShowTechnicalMetaKey, next);
    if (!mounted) {
      return;
    }
    setState(() {
      _showTechnicalMeta = next;
    });
  }

  String? _providerOrderOverride() {
    switch (_chatProviderPriority) {
      case 'groq_first':
        return 'groq,gemini';
      case 'gemini_first':
        return 'gemini,groq';
      default:
        return 'groq,gemini';
    }
  }

  String _chatProviderPriorityLabel() {
    switch (_chatProviderPriority) {
      case 'groq_first':
        return 'Groq dulu';
      case 'gemini_first':
        return 'Gemini dulu';
      default:
        return 'Groq dulu';
    }
  }

  Future<void> _sendFromInput() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _inputController.clear();
    await _sendQuestion(text);
  }

  void _resetChat() {
    _pendingDraft = null;
    _pendingDraftMessageIndex = null;
    _pendingDraftCreatedAtEpochMs = null;
    _assistantFeedback.clear();
    _messages
      ..clear()
      ..add(
        const AiChatMessage(
          role: 'assistant',
          text:
              'Halo, saya Asisten Mom Fiqry. Saya bisa bantu analisis data keuangan toko dan menyiapkan draf transaksi dari chat.',
        ),
      );
  }

  String _snapshotHash() {
    final payload = jsonEncode(widget.financeSnapshot);
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<void> _loadPersistedChat() async {
    _resetChat();
    final prefs = await SharedPreferences.getInstance();
    final currentSnapshotHash = _snapshotHash();
    final snapshotHash = prefs.getString(_chatSnapshotKey);
    final historyRaw = prefs.getString(_chatStoreKey);
    if (snapshotHash == null ||
        historyRaw == null ||
        snapshotHash != currentSnapshotHash) {
      await prefs.remove(_chatPendingDraftKey);
      await prefs.remove(_chatPendingDraftMetaKey);
      await prefs.remove(_chatPendingDraftSnapshotKey);
      await _prepareInitialDraftFlowIfAny();
      _prepareInitialQuestionFlowIfAny();
      return;
    }

    try {
      final decoded = jsonDecode(historyRaw);
      if (decoded is! List) {
        return;
      }
      final restored =
          decoded
              .map((row) {
                if (row is! Map) {
                  return null;
                }
                final map = Map<String, dynamic>.from(row);
                final role = (map['role'] ?? '').toString().trim();
                final text = (map['text'] ?? '').toString().trim();
                final providerId = (map['provider_id'] ?? '').toString().trim();
                final confidenceLevel =
                    (map['confidence_level'] ?? '').toString().trim();
                final confidenceReason =
                    (map['confidence_reason'] ?? '').toString().trim();
                final executionPath =
                    (map['execution_path'] ?? '').toString().trim();
                final executionReason =
                    (map['execution_reason'] ?? '').toString().trim();
                if ((role != 'user' && role != 'assistant') || text.isEmpty) {
                  return null;
                }
                return AiChatMessage(
                  role: role,
                  text: text,
                  providerId: providerId.isEmpty ? null : providerId,
                  confidenceLevel:
                      confidenceLevel.isEmpty ? null : confidenceLevel,
                  confidenceReason:
                      confidenceReason.isEmpty ? null : confidenceReason,
                  executionPath: executionPath.isEmpty ? null : executionPath,
                  executionReason:
                      executionReason.isEmpty ? null : executionReason,
                );
              })
              .whereType<AiChatMessage>()
              .toList();
      if (restored.isNotEmpty) {
        _messages
          ..clear()
          ..addAll(restored);
      }
    } catch (_) {
      // Keep default chat state and still continue initial-question flow.
    }

    final pendingDraftRaw = prefs.getString(_chatPendingDraftKey);
    final pendingDraftSnapshot = prefs.getString(_chatPendingDraftSnapshotKey);
    final pendingMetaRaw = prefs.getString(_chatPendingDraftMetaKey);
    if (pendingDraftRaw != null &&
        pendingDraftSnapshot == currentSnapshotHash &&
        pendingDraftRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(pendingDraftRaw);
        if (decoded is Map<String, dynamic>) {
          final parsed = ChatImportDraft.fromJson(decoded);
          if (parsed.transactions.isNotEmpty) {
            _pendingDraft = parsed;
          }
        } else if (decoded is Map) {
          final parsed = ChatImportDraft.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (parsed.transactions.isNotEmpty) {
            _pendingDraft = parsed;
          }
        }
      } catch (_) {
        _pendingDraft = null;
        _pendingDraftCreatedAtEpochMs = null;
      }
      if (_pendingDraft != null && pendingMetaRaw != null) {
        try {
          final metaDecoded = jsonDecode(pendingMetaRaw);
          if (metaDecoded is Map<String, dynamic>) {
            _pendingDraftCreatedAtEpochMs = _toIntOrNull(
              metaDecoded['created_at_epoch_ms'],
            );
          } else if (metaDecoded is Map) {
            final map = Map<String, dynamic>.from(metaDecoded);
            _pendingDraftCreatedAtEpochMs = _toIntOrNull(
              map['created_at_epoch_ms'],
            );
          }
        } catch (_) {
          _pendingDraftCreatedAtEpochMs = null;
        }
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {});
    await _prepareInitialDraftFlowIfAny();
    _prepareInitialQuestionFlowIfAny();
  }

  Future<void> _prepareInitialQuestionFlowIfAny() async {
    if (_initialQuestionHandled || !mounted) {
      return;
    }
    final initial = widget.initialQuestion?.trim();
    if (initial == null || initial.isEmpty) {
      _initialQuestionHandled = true;
      return;
    }
    _initialQuestionHandled = true;

    var useExistingContext = true;
    final hasPersistedConversation = _messages.length > 1;
    if (hasPersistedConversation) {
      final decision = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Lanjutkan atau Mulai Baru?'),
              content: const Text(
                'Terdapat riwayat chat sebelumnya. Lanjutkan konteks lama atau mulai chat baru?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Mulai Baru'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Lanjutkan'),
                ),
              ],
            ),
      );
      if (!mounted || decision == null) {
        return;
      }
      useExistingContext = decision;
    }

    if (!useExistingContext) {
      setState(_resetChat);
      await _persistChat();
    }

    setState(() {
      _pendingInitialQuestion = initial;
    });
  }

  Future<void> _persistChat() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _messages
          .map(
            (m) => {
              'role': m.role,
              'text': m.text,
              if (m.providerId != null && m.providerId!.trim().isNotEmpty)
                'provider_id': m.providerId,
              if (m.confidenceLevel != null &&
                  m.confidenceLevel!.trim().isNotEmpty)
                'confidence_level': m.confidenceLevel,
              if (m.confidenceReason != null &&
                  m.confidenceReason!.trim().isNotEmpty)
                'confidence_reason': m.confidenceReason,
              if (m.executionPath != null && m.executionPath!.trim().isNotEmpty)
                'execution_path': m.executionPath,
              if (m.executionReason != null &&
                  m.executionReason!.trim().isNotEmpty)
                'execution_reason': m.executionReason,
            },
          )
          .toList(growable: false),
    );
    await prefs.setString(_chatStoreKey, encoded);
    await prefs.setString(_chatSnapshotKey, _snapshotHash());
    await prefs.setInt(_chatSavedAtKey, DateTime.now().millisecondsSinceEpoch);
    await _persistPendingDraft(prefs);
  }

  Future<void> _persistPendingDraft(SharedPreferences prefs) async {
    final draft = _pendingDraft;
    if (draft == null) {
      await prefs.remove(_chatPendingDraftKey);
      await prefs.remove(_chatPendingDraftMetaKey);
      await prefs.remove(_chatPendingDraftSnapshotKey);
      return;
    }
    _pendingDraftCreatedAtEpochMs ??= DateTime.now().millisecondsSinceEpoch;
    await prefs.setString(_chatPendingDraftKey, jsonEncode(draft.toJson()));
    await prefs.setString(_chatPendingDraftSnapshotKey, _snapshotHash());
    await prefs.setString(
      _chatPendingDraftMetaKey,
      jsonEncode(<String, dynamic>{
        'created_at_epoch_ms': _pendingDraftCreatedAtEpochMs,
        'source': draft.source,
        'import_hash': draft.importHash,
      }),
    );
  }

  int? _toIntOrNull(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse((value ?? '').toString());
  }

  Future<void> _prepareInitialDraftFlowIfAny() async {
    if (_initialDraftHandled || !mounted) {
      return;
    }
    _initialDraftHandled = true;
    final inboundDraft = widget.initialDraft;
    if (inboundDraft == null || inboundDraft.transactions.isEmpty) {
      return;
    }

    if (_pendingDraft != null &&
        _pendingDraft!.importHash.trim() == inboundDraft.importHash.trim()) {
      return;
    }
    if (_pendingDraft != null && _pendingDraft!.transactions.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Ganti Draft Pending?'),
              content: const Text(
                'Masih ada draft chat yang belum selesai. Ganti dengan draft OCR terbaru?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Pertahankan Draft Lama'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Ganti Draft'),
                ),
              ],
            ),
      );
      if (!mounted || replace != true) {
        return;
      }
    }

    final auditText = widget.initialDraftAuditText?.trim() ?? '';
    final intro = <String>[
      if (auditText.isNotEmpty) 'Audit OCR mentah:\n$auditText',
      _buildDraftSummary(inboundDraft),
    ].join('\n\n');
    setState(() {
      _pendingDraft = inboundDraft;
      _pendingDraftCreatedAtEpochMs = DateTime.now().millisecondsSinceEpoch;
      _messages.add(
        const AiChatMessage(
          role: 'assistant',
          text: 'Memuat draf OCR untuk diedit di chat...',
          providerId: 'local-ocr-bridge',
          confidenceLevel: 'high',
          confidenceReason: 'Draft OCR diteruskan ke mode chat untuk review.',
          executionPath: 'local',
          executionReason: 'routing_ocr_accurate_to_chat',
        ),
      );
      _messages.add(
        AiChatMessage(
          role: 'assistant',
          text: intro,
          providerId: 'local-ocr-bridge',
          confidenceLevel: 'high',
          confidenceReason: 'Ringkasan OCR mentah ditampilkan untuk audit.',
          executionPath: 'local',
          executionReason: 'drafting_bootstrap',
        ),
      );
      _pendingDraftMessageIndex = _messages.length - 1;
    });
    await _persistChat();
    _scrollToBottom();
  }

  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Hapus Percakapan'),
            content: const Text('Riwayat chat di layar ini akan dihapus.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Hapus'),
              ),
            ],
          ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    setState(_resetChat);
    await _persistChat();
    _scrollToBottom();
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    await HapticFeedback.selectionClick();
  }

  void _editUserMessage(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
    HapticFeedback.selectionClick();
  }

  Future<void> _sendQuestion(String question) async {
    if (_isLoading || _cooldownSeconds > 0) {
      return;
    }

    setState(() {
      _isLoading = true;
      _messages.add(AiChatMessage(role: 'user', text: question));
    });
    await _persistChat();
    _scrollToBottom();

    final normalized = question.trim().toLowerCase();
    if (_pendingDraft != null && _isPendingDraftConfirmation(normalized)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          const AiChatMessage(
            role: 'assistant',
            text: 'Siap, saya lanjutkan ke layar review draf transaksi.',
            providerId: 'local-context',
            confidenceLevel: 'high',
            confidenceReason:
                'Konfirmasi lanjutan draf terdeteksi dari konteks chat.',
            executionPath: 'local',
            executionReason:
                'Konfirmasi user untuk draf pending diproses lokal.',
          ),
        );
      });
      await _persistChat();
      _scrollToBottom();
      await _openPendingDraft();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }
    if (_pendingDraft != null) {
      final editFeedback = _tryApplyPendingDraftEdit(question);
      if (editFeedback != null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _messages.add(
            AiChatMessage(
              role: 'assistant',
              text: editFeedback,
              providerId: 'local-draft-edit',
              confidenceLevel: 'high',
              confidenceReason: 'Perubahan draf diproses dari konteks chat.',
              executionPath: 'local',
              executionReason: 'Perintah edit draf terdeteksi dari teks.',
            ),
          );
          _pendingDraftMessageIndex = _messages.length - 1;
        });
        await _persistChat();
        _scrollToBottom();
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
    }

    if (_isChatHistoryIntent(normalized)) {
      final summary = _buildRecentChatSummary(currentPrompt: question);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          AiChatMessage(
            role: 'assistant',
            text: summary,
            providerId: 'local-context',
            confidenceLevel: 'high',
            confidenceReason:
                'Permintaan ringkasan riwayat chat diproses dari memori percakapan lokal.',
            executionPath: 'local',
            executionReason:
                'Ringkasan diambil dari daftar pesan pada sesi ini.',
          ),
        );
      });
      await _persistChat();
      _scrollToBottom();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final normalizedQuestionKey = _normalizeIntentKey(question);
    final shouldAutoEscalate =
        _isLikelyRetryQuestion(normalizedQuestionKey) ||
        _matchesEscalationPhrase(normalizedQuestionKey);
    final effectiveMode = shouldAutoEscalate ? 'flexible' : 'safe';

    try {
      final reply = await _chatbotService.askFinancialAssistant(
        question: question,
        financeSnapshot: widget.financeSnapshot,
        history: _messages,
        providerOrderOverride: _providerOrderOverride(),
        intentRoutingMode: effectiveMode,
      );
      if (!mounted) {
        return;
      }
      if (reply.actionDraft != null) {
        final summary = _buildDraftSummary(reply.actionDraft!);
        setState(() {
          _messages.add(
            AiChatMessage(
              role: 'assistant',
              text: summary,
              providerId: reply.providerId,
              confidenceLevel: reply.confidenceLevel,
              confidenceReason: reply.confidenceReason,
              executionPath: reply.executionPath,
              executionReason: reply.executionReason,
            ),
          );
          _pendingDraft = reply.actionDraft;
          _pendingDraftCreatedAtEpochMs = DateTime.now().millisecondsSinceEpoch;
          _pendingDraftMessageIndex = _messages.length - 1;
        });
      } else {
        setState(() {
          _messages.add(
            AiChatMessage(
              role: 'assistant',
              text: reply.text,
              providerId: reply.providerId,
              confidenceLevel: reply.confidenceLevel,
              confidenceReason: reply.confidenceReason,
              executionPath: reply.executionPath,
              executionReason: reply.executionReason,
            ),
          );
        });
      }
      await _persistChat();
      if (!mounted) {
        return;
      }
      _startCooldown(reply.suggestedCooldownSeconds);
      _scrollToBottom();
    } on AiRateLimitException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          AiChatMessage(
            role: 'assistant',
            text: error.toString(),
            providerId: 'error',
            confidenceLevel: 'low',
            confidenceReason:
                'Provider mengembalikan rate-limit/error sementara.',
            executionPath: 'llm',
            executionReason: 'Request gagal di sisi provider AI.',
          ),
        );
      });
      await _persistChat();
      if (!error.isDailyLimit) {
        _startCooldown(error.retryAfterSeconds);
      }
      _scrollToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final raw = error.toString().trim();
      final userMessage =
          raw.startsWith('Exception:') ? raw.substring(10).trim() : raw;
      setState(() {
        _messages.add(
          AiChatMessage(
            role: 'assistant',
            text:
                userMessage.isEmpty
                    ? 'Gagal memproses pertanyaan. Coba lagi.'
                    : userMessage,
            providerId: 'error',
            confidenceLevel: 'low',
            confidenceReason: 'Terjadi error saat memproses jawaban AI.',
            executionPath: 'llm',
            executionReason: 'Request gagal di sisi provider AI.',
          ),
        );
      });
      await _persistChat();
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isPendingDraftConfirmation(String normalized) {
    const tokens = <String>[
      'sudah benar',
      'sudah oke',
      'sudah ok',
      'oke',
      'ok',
      'ya',
      'iya',
      'lanjut',
      'lanjutkan',
      'setuju',
      'benar',
      'lanjut review',
      'ke review',
      'review saja',
    ];
    return tokens.any(
      (token) => normalized == token || normalized.contains(token),
    );
  }

  String? _tryApplyPendingDraftEdit(String question) {
    final draft = _pendingDraft;
    if (draft == null || draft.transactions.isEmpty) {
      return null;
    }
    final normalized = question.toLowerCase().trim();
    final isEditIntent = RegExp(
      r'\b(ubah|ganti|jadi|set|hapus|delete)\b',
    ).hasMatch(normalized);
    if (!isEditIntent) {
      return null;
    }

    if (normalized.contains('hapus ') || normalized == 'hapus') {
      final targetIndex = _resolveDraftTargetIndex(
        normalized: normalized,
        draft: draft,
        fallbackToFirst: draft.transactions.length == 1,
      );
      if (targetIndex == null) {
        return 'Saya belum tahu item mana yang dihapus. Contoh: "hapus item 1" atau "hapus donat".';
      }
      final removed = draft.transactions[targetIndex];
      final nextItems = List<ChatImportDraftItem>.from(draft.transactions)
        ..removeAt(targetIndex);
      if (nextItems.isEmpty) {
        _pendingDraft = null;
        _pendingDraftMessageIndex = null;
        _pendingDraftCreatedAtEpochMs = null;
        return 'Semua item draf sudah dihapus.';
      }
      _pendingDraft = draft.copyWith(transactions: nextItems);
      return 'Item "${removed.description}" dihapus dari draf.\n\n${_buildDraftSummary(_pendingDraft!)}';
    }

    final nextType = _extractDraftTypeUpdate(normalized);
    if (nextType != null) {
      final targetIndex = _resolveDraftTargetIndex(
        normalized: normalized,
        draft: draft,
        fallbackToFirst: draft.transactions.length == 1,
      );
      if (targetIndex == null) {
        return 'Saya belum tahu item mana yang diubah tipenya. Contoh: "ubah item 1 jadi keluar".';
      }
      final current = draft.transactions[targetIndex];
      if (current.type == nextType) {
        return 'Tipe transaksi sudah ${nextType == 'IN' ? 'MASUK' : 'KELUAR'}.';
      }
      final updated = List<ChatImportDraftItem>.from(draft.transactions);
      updated[targetIndex] = current.copyWith(
        type: nextType,
        needsReview: false,
      );
      _pendingDraft = draft.copyWith(transactions: updated);
      return 'Tipe "${current.description}" diubah menjadi ${nextType == 'IN' ? 'MASUK' : 'KELUAR'}.\n\n${_buildDraftSummary(_pendingDraft!)}';
    }

    final nextDateIso = _extractDraftDateIso(question);
    if (nextDateIso != null) {
      final targetIndex = _resolveDraftTargetIndex(
        normalized: normalized,
        draft: draft,
        fallbackToFirst: draft.transactions.length == 1,
      );
      if (targetIndex == null) {
        return 'Saya belum tahu item mana yang diubah tanggalnya. Contoh: "ubah tanggal item 1 jadi hari ini".';
      }
      final current = draft.transactions[targetIndex];
      final updated = List<ChatImportDraftItem>.from(draft.transactions);
      updated[targetIndex] = current.copyWith(
        dateIso: nextDateIso,
        dateSource: 'explicit',
        needsReview: false,
      );
      _pendingDraft = draft.copyWith(transactions: updated);
      return 'Tanggal "${current.description}" diubah menjadi $nextDateIso.\n\n${_buildDraftSummary(_pendingDraft!)}';
    }

    final amounts = _extractAmountsFromText(question);
    if (amounts.isEmpty) {
      final descriptionUpdate = _extractDraftDescriptionUpdate(question);
      if (descriptionUpdate == null) {
        return null;
      }
      final targetIndex = _resolveDraftTargetIndex(
        normalized: normalized,
        draft: draft,
        descriptionHint: descriptionUpdate.sourceHint,
        fallbackToFirst:
            draft.transactions.length == 1 ||
            descriptionUpdate.sourceHint.trim().isEmpty,
      );
      if (targetIndex == null) {
        return 'Saya belum tahu item mana yang diubah namanya. Contoh: "ubah nama donat jadi donat coklat".';
      }
      final current = draft.transactions[targetIndex];
      final nextDesc = descriptionUpdate.newDescription.trim();
      if (nextDesc.isEmpty || nextDesc == current.description.trim()) {
        return null;
      }
      final updated = List<ChatImportDraftItem>.from(draft.transactions);
      updated[targetIndex] = current.copyWith(
        description: nextDesc,
        needsReview: false,
      );
      _pendingDraft = draft.copyWith(transactions: updated);
      return 'Nama item "${current.description}" diubah menjadi "$nextDesc".\n\n${_buildDraftSummary(_pendingDraft!)}';
    }

    final descTarget = _extractDescriptionTarget(normalized);
    final targetIndex =
        _resolveDraftTargetIndex(
          normalized: normalized,
          draft: draft,
          descriptionHint: descTarget,
          fallbackToFirst: true,
        ) ??
        0;
    final currentItem = draft.transactions[targetIndex];
    final oldAmount = currentItem.amount;

    int? newAmount;
    if (amounts.length >= 2) {
      final from = amounts[0];
      final to = amounts[1];
      if (oldAmount == from ||
          draft.transactions.any((item) => item.amount == from)) {
        newAmount = to;
      } else {
        newAmount = to;
      }
    } else if (draft.transactions.length == 1) {
      newAmount = amounts.first;
    }

    if (newAmount == null || newAmount <= 0 || newAmount == oldAmount) {
      return null;
    }

    final updatedItems = List<ChatImportDraftItem>.from(draft.transactions);
    updatedItems[targetIndex] = currentItem.copyWith(
      amount: newAmount,
      needsReview: false,
      warning: '',
    );
    _pendingDraft = draft.copyWith(transactions: updatedItems);

    final fromText = NumberFormat('#,##0', 'id_ID').format(oldAmount);
    final toText = NumberFormat('#,##0', 'id_ID').format(newAmount);
    final summary = _buildDraftSummary(_pendingDraft!);
    return 'Siap, nominal ${currentItem.description} diubah dari Rp $fromText menjadi Rp $toText.\n\n$summary';
  }

  int? _resolveDraftTargetIndex({
    required String normalized,
    required ChatImportDraft draft,
    String? descriptionHint,
    required bool fallbackToFirst,
  }) {
    final itemMatch = RegExp(
      r'\b(?:item|transaksi)\s+(\d{1,2})\b',
    ).firstMatch(normalized);
    if (itemMatch != null) {
      final raw = int.tryParse(itemMatch.group(1) ?? '');
      if (raw != null && raw >= 1 && raw <= draft.transactions.length) {
        return raw - 1;
      }
    }

    final hint = (descriptionHint ?? '').trim().toLowerCase();
    if (hint.isNotEmpty) {
      final matched = <int>[];
      for (var i = 0; i < draft.transactions.length; i++) {
        final desc = draft.transactions[i].description.toLowerCase();
        if (desc.contains(hint)) {
          matched.add(i);
        }
      }
      if (matched.length == 1) {
        return matched.first;
      }
      if (matched.length > 1 && fallbackToFirst) {
        return matched.first;
      }
    }

    if (fallbackToFirst && draft.transactions.isNotEmpty) {
      return 0;
    }
    return null;
  }

  String? _extractDraftTypeUpdate(String normalized) {
    final wantsOut =
        RegExp(r'\b(jadi|ubah|set|ke)\s+(out|keluar)\b').hasMatch(normalized) ||
        RegExp(r'\b(out|keluar)\b').hasMatch(normalized) &&
            (normalized.contains('jadi') || normalized.contains('ubah'));
    if (wantsOut) {
      return 'OUT';
    }
    final wantsIn =
        RegExp(r'\b(jadi|ubah|set|ke)\s+(in|masuk)\b').hasMatch(normalized) ||
        RegExp(r'\b(in|masuk)\b').hasMatch(normalized) &&
            (normalized.contains('jadi') || normalized.contains('ubah'));
    if (wantsIn) {
      return 'IN';
    }
    return null;
  }

  String? _extractDraftDateIso(String input) {
    final normalized = input.toLowerCase();
    final now = DateTime.now();
    if (normalized.contains('hari ini')) {
      return DateFormat('yyyy-MM-dd').format(now);
    }
    if (normalized.contains('kemarin')) {
      return DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 1)));
    }
    final isoMatch = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b').firstMatch(normalized);
    if (isoMatch != null) {
      final value = isoMatch.group(1)!;
      if (DateTime.tryParse(value) != null) {
        return value;
      }
    }
    final dmyMatch = RegExp(
      r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b',
    ).firstMatch(normalized);
    if (dmyMatch == null) {
      return null;
    }
    final day = int.tryParse(dmyMatch.group(1) ?? '');
    final month = int.tryParse(dmyMatch.group(2) ?? '');
    final yearRaw = int.tryParse(dmyMatch.group(3) ?? '');
    if (day == null || month == null || yearRaw == null) {
      return null;
    }
    final year = yearRaw < 100 ? 2000 + yearRaw : yearRaw;
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return DateFormat('yyyy-MM-dd').format(parsed);
  }

  _DraftDescriptionUpdate? _extractDraftDescriptionUpdate(String input) {
    final normalized = input.toLowerCase().trim();
    final regex = RegExp(
      r"(?:ubah|ganti)\s+(?:nama|keterangan)?\s*([a-z0-9 ,.'-]{2,40}?)\s+(?:jadi|ke)\s+([a-z0-9 ,.'-]{2,80})$",
      caseSensitive: false,
    );
    final match = regex.firstMatch(normalized);
    if (match != null) {
      final nextDescription = (match.group(2) ?? '').trim();
      if (_looksLikeAmountOnlyPhrase(nextDescription)) {
        return null;
      }
      return _DraftDescriptionUpdate(
        sourceHint: (match.group(1) ?? '').trim(),
        newDescription: _toTitleWords(nextDescription),
      );
    }

    final generic = RegExp(
      r"(?:ubah|ganti)\s+(?:nama|keterangan)\s+(?:jadi|ke)\s+([a-z0-9 ,.'-]{2,80})$",
      caseSensitive: false,
    ).firstMatch(normalized);
    if (generic == null) {
      return null;
    }
    final nextDescription = (generic.group(1) ?? '').trim();
    if (_looksLikeAmountOnlyPhrase(nextDescription)) {
      return null;
    }
    return _DraftDescriptionUpdate(
      sourceHint: '',
      newDescription: _toTitleWords(nextDescription),
    );
  }

  bool _looksLikeAmountOnlyPhrase(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return RegExp(
      r'^\d+(?:[.,]\d+)?\s*(k|rb|ribu|jt|juta)?$',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  String _toTitleWords(String value) {
    final words = value
        .split(RegExp(r'\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          if (lower.length <= 1) {
            return lower.toUpperCase();
          }
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .toList(growable: false);
    return words.join(' ');
  }

  String? _extractDescriptionTarget(String normalized) {
    final tokens = normalized
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    const ignored = <String>{
      'ubah',
      'ganti',
      'jadi',
      'ke',
      'dari',
      'rp',
      'ribu',
      'rb',
      'k',
      'jt',
      'juta',
      'nominal',
    };
    for (final token in tokens) {
      if (ignored.contains(token)) {
        continue;
      }
      if (RegExp(r'^\d+$').hasMatch(token)) {
        continue;
      }
      return token;
    }
    return null;
  }

  List<int> _extractAmountsFromText(String input) {
    final matches = RegExp(
      r'(\d{1,3}(?:[.,]\d{3})+|\d+)\s*(k|rb|ribu|jt|juta)?',
      caseSensitive: false,
    ).allMatches(input);
    final result = <int>[];
    for (final m in matches) {
      final rawNumber = (m.group(1) ?? '').trim();
      final unit = (m.group(2) ?? '').trim().toLowerCase();
      if (rawNumber.isEmpty) {
        continue;
      }
      final normalizedNumber = rawNumber.replaceAll(RegExp(r'[.,]'), '');
      final parsed = int.tryParse(normalizedNumber);
      if (parsed == null) {
        continue;
      }
      var multiplier = 1;
      if (unit == 'k' || unit == 'rb' || unit == 'ribu') {
        multiplier = 1000;
      } else if (unit == 'jt' || unit == 'juta') {
        multiplier = 1000000;
      }
      result.add(parsed * multiplier);
    }
    return result;
  }

  bool _isChatHistoryIntent(String normalized) {
    const tokens = <String>[
      'chat sebelumnya',
      'riwayat chat',
      'pesan sebelumnya',
      'percakapan sebelumnya',
      'history chat',
      'ringkas chat',
      'rekap chat',
    ];
    return tokens.any((token) => normalized.contains(token));
  }

  String _buildRecentChatSummary({required String currentPrompt}) {
    final normalizedCurrent = currentPrompt.trim().toLowerCase();
    final userMessages =
        _messages
            .where((m) => m.role == 'user')
            .map((m) => m.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
    final filtered =
        userMessages
            .where((text) => text.toLowerCase() != normalizedCurrent)
            .toList();

    if (filtered.isEmpty) {
      return 'Di sesi ini belum ada riwayat chat yang bisa diringkas.';
    }

    final last =
        filtered.length <= 4 ? filtered : filtered.sublist(filtered.length - 4);
    final lines = <String>[
      'Ringkasan chat sebelumnya di sesi ini:',
      for (var i = 0; i < last.length; i++) '- ${i + 1}. ${last[i]}',
    ];
    if (_pendingDraft != null) {
      lines.add(
        'Masih ada draf transaksi yang siap direview. Ketik "lanjut" atau tekan tombol "Lanjut ke Review".',
      );
    }
    return lines.join('\n');
  }

  String _normalizeIntentKey(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _matchesEscalationPhrase(String normalizedQuestionKey) {
    if (normalizedQuestionKey.isEmpty) {
      return false;
    }
    if (_escalationPhrases.contains(normalizedQuestionKey)) {
      return true;
    }
    final questionTokens = _tokenizeIntent(normalizedQuestionKey);
    if (questionTokens.isEmpty) {
      return false;
    }
    for (final phrase in _escalationPhrases) {
      final phraseTokens = _tokenizeIntent(phrase);
      if (phraseTokens.isEmpty) {
        continue;
      }
      final intersection = questionTokens.intersection(phraseTokens).length;
      final overlap =
          intersection /
          (questionTokens.length > phraseTokens.length
              ? questionTokens.length
              : phraseTokens.length);
      if (overlap >= 0.6) {
        return true;
      }
    }
    return false;
  }

  Set<String> _tokenizeIntent(String value) {
    return value
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty && token.length > 1)
        .toSet();
  }

  bool _isLikelyRetryQuestion(String normalizedQuestion) {
    if (normalizedQuestion.isEmpty) {
      return false;
    }
    String? previousUserQuestion;
    AiChatMessage? previousAssistant;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (previousUserQuestion == null && msg.role == 'user') {
        previousUserQuestion = _normalizeIntentKey(msg.text);
        continue;
      }
      if (previousAssistant == null && msg.role == 'assistant') {
        previousAssistant = msg;
      }
      if (previousUserQuestion != null && previousAssistant != null) {
        break;
      }
    }
    if (previousUserQuestion == null ||
        previousUserQuestion != normalizedQuestion) {
      return false;
    }
    final provider = previousAssistant?.providerId?.trim().toLowerCase() ?? '';
    final lowConfidence =
        (previousAssistant?.confidenceLevel ?? '').toLowerCase() != 'high';
    return provider == 'local-clarification' ||
        provider == 'local-scope-guard' ||
        lowConfidence;
  }

  String? _nearestUserQuestionForAssistantIndex(int assistantIndex) {
    for (var i = assistantIndex - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.role == 'user') {
        final normalized = _normalizeIntentKey(msg.text);
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }
    return null;
  }

  Future<void> _setAssistantFeedback({
    required int messageIndex,
    required int value,
  }) async {
    final nearestQuestion = _nearestUserQuestionForAssistantIndex(messageIndex);
    if (nearestQuestion == null) {
      return;
    }
    final next = Set<String>.from(_escalationPhrases);
    if (value < 0) {
      next.add(nearestQuestion);
    } else {
      next.remove(nearestQuestion);
    }
    await DatabaseHelper.instance.upsertChatLearningFeedback(
      phraseKey: nearestQuestion,
      feedbackValue: value,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _assistantFeedback[messageIndex] = value;
      _escalationPhrases = next;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value < 0
              ? 'Masukan disimpan. Pertanyaan serupa akan diproses lebih luwes.'
              : 'Terima kasih. Pertanyaan serupa diproses dengan aturan ketat.',
        ),
      ),
    );
  }

  bool _shouldShowFeedback(AiChatMessage msg) {
    if (msg.role != 'assistant') {
      return false;
    }
    final provider = (msg.providerId ?? '').trim().toLowerCase();
    if (provider.isEmpty) {
      return false;
    }
    if (provider.startsWith('local-') || provider == 'error') {
      return false;
    }
    final executionPath = (msg.executionPath ?? '').trim().toLowerCase();
    if (executionPath != 'llm') {
      return false;
    }
    return provider.contains('groq') || provider.contains('gemini');
  }

  String _buildDraftSummary(ChatImportDraft draft) {
    final count = draft.transactions.length;
    final total = draft.transactions.fold<int>(
      0,
      (sum, item) => sum + item.amount,
    );
    final inferredCount =
        draft.transactions
            .where((item) => item.dateSource == 'inferred')
            .length;
    final needsReview =
        draft.transactions.where((item) => item.needsReview).length;
    final dateLabels =
        draft.transactions
            .map((item) => item.dateIso.trim())
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final dateText =
        dateLabels.isEmpty
            ? '(tanggal perlu konfirmasi)'
            : dateLabels.join(', ');
    final totalText = NumberFormat('#,##0', 'id_ID').format(total);
    return 'Draf transaksi siap ditinjau.\n'
        '- Item: $count\n'
        '- Total: Rp $totalText\n'
        '- Tanggal: $dateText\n'
        '- Perlu review: $needsReview item'
        '${inferredCount > 0 ? ' (termasuk $inferredCount inferensi tanggal)' : ''}.\n'
        'Tekan tombol di bawah untuk lanjut ke layar review.';
  }

  Future<void> _openPendingDraft() async {
    final draft = _pendingDraft;
    if (draft == null) {
      return;
    }
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OcrAssistScreen(chatImportDraft: draft),
      ),
    );
    if (!mounted) {
      return;
    }
    final savedFromChatImport =
        result is Map &&
        result['saved'] == true &&
        result['source'] == 'chat-import';
    if (savedFromChatImport) {
      setState(() {
        _pendingDraft = null;
        _pendingDraftMessageIndex = null;
        _pendingDraftCreatedAtEpochMs = null;
      });
      await _persistChat();
    }
    if (savedFromChatImport) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
    }
  }

  Future<void> _exitDraftingMode() async {
    if (_pendingDraft == null) {
      return;
    }
    final shouldExit = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Keluar Mode Draft?'),
            content: const Text(
              'Draft OCR yang sedang diedit akan dibatalkan dan dihapus dari chat.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Tidak'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Ya, Keluar'),
              ),
            ],
          ),
    );
    if (shouldExit != true || !mounted) {
      return;
    }
    setState(() {
      _pendingDraft = null;
      _pendingDraftMessageIndex = null;
      _pendingDraftCreatedAtEpochMs = null;
      _messages.add(
        const AiChatMessage(
          role: 'assistant',
          text: 'Mode edit draft ditutup. Kita kembali ke chat biasa.',
          providerId: 'local-draft-exit',
          confidenceLevel: 'high',
          confidenceReason: 'User keluar dari mode drafting.',
          executionPath: 'local',
          executionReason: 'drafting_exit',
        ),
      );
    });
    await _persistChat();
    _scrollToBottom();
  }

  void _startCooldown(int seconds) {
    final safeSeconds = seconds < 1 ? 1 : seconds;
    _cooldownTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _cooldownSeconds = safeSeconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _cooldownSeconds = 0;
        });
        return;
      }
      setState(() {
        _cooldownSeconds -= 1;
      });
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten Mom Fiqry'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Prioritas provider AI',
            initialValue: _chatProviderPriority,
            onSelected: _setChatProviderPriority,
            itemBuilder:
                (context) => const [
                  PopupMenuItem<String>(
                    value: 'groq_first',
                    child: Text('Groq dulu (Rekomendasi)'),
                  ),
                  PopupMenuItem<String>(
                    value: 'gemini_first',
                    child: Text('Gemini dulu'),
                  ),
                ],
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip:
                _showTechnicalMeta
                    ? 'Sembunyikan info teknis'
                    : 'Tampilkan info teknis',
            onPressed: _toggleTechnicalMeta,
            icon: Icon(
              _showTechnicalMeta
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Hapus chat',
            onPressed: _messages.length <= 1 ? null : _clearChat,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
              children:
                  [
                    if (_pendingInitialQuestion != null &&
                        _pendingInitialQuestion!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: const Text('Gunakan Tanya Lanjutan'),
                          onPressed:
                              (_isLoading || _cooldownSeconds > 0)
                                  ? null
                                  : () async {
                                    final text =
                                        _pendingInitialQuestion?.trim() ?? '';
                                    if (text.isEmpty) {
                                      return;
                                    }
                                    setState(() {
                                      _pendingInitialQuestion = null;
                                    });
                                    await _sendQuestion(text);
                                  },
                        ),
                      ),
                  ] +
                  _quickQuestions
                      .map(
                        (q) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(q),
                            onPressed:
                                (_isLoading || _cooldownSeconds > 0)
                                    ? null
                                    : () => _sendQuestion(q),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Prioritas AI: ${_chatProviderPriorityLabel()}',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ),
          if (_pendingDraft != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE0B2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.edit_note, size: 16, color: Colors.black87),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Mode Edit Draf OCR aktif',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              (_isLoading || _cooldownSeconds > 0)
                                  ? null
                                  : _openPendingDraft,
                          icon: const Icon(Icons.playlist_add_check),
                          label: const Text('Lanjut ke Review'),
                        ),
                        TextButton.icon(
                          onPressed:
                              (_isLoading || _cooldownSeconds > 0)
                                  ? null
                                  : _exitDraftingMode,
                          icon: const Icon(Icons.close),
                          label: const Text('Keluar Mode Draft'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('AI sedang mengetik...'),
                    ),
                  );
                }
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color:
                          isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          isUser
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                      children: [
                        Text(msg.text),
                        if (!isUser &&
                            _pendingDraft != null &&
                            _pendingDraftMessageIndex == index)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed:
                                      (_isLoading || _cooldownSeconds > 0)
                                          ? null
                                          : _openPendingDraft,
                                  icon: const Icon(Icons.playlist_add_check),
                                  label: const Text('Lanjut ke Review'),
                                ),
                                OutlinedButton(
                                  onPressed:
                                      (_isLoading || _cooldownSeconds > 0)
                                          ? null
                                          : () {
                                            setState(() {
                                              _pendingDraftMessageIndex = null;
                                            });
                                          },
                                  child: const Text('Edit di Chat Dulu'),
                                ),
                              ],
                            ),
                          ),
                        if (!isUser && _shouldShowFeedback(msg))
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Jawaban membantu',
                                  onPressed:
                                      () => _setAssistantFeedback(
                                        messageIndex: index,
                                        value: 1,
                                      ),
                                  icon: Icon(
                                    (_assistantFeedback[index] ?? 0) == 1
                                        ? Icons.thumb_up
                                        : Icons.thumb_up_outlined,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Jawaban kurang tepat',
                                  onPressed:
                                      () => _setAssistantFeedback(
                                        messageIndex: index,
                                        value: -1,
                                      ),
                                  icon: Icon(
                                    (_assistantFeedback[index] ?? 0) == -1
                                        ? Icons.thumb_down
                                        : Icons.thumb_down_outlined,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip:
                                    isUser ? 'Salin pesan' : 'Salin jawaban',
                                onPressed: () => _copyMessage(msg.text),
                                icon: const Icon(Icons.copy_outlined, size: 18),
                              ),
                              if (isUser)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Edit & kirim ulang',
                                  onPressed: () => _editUserMessage(msg.text),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_showTechnicalMeta &&
                            !isUser &&
                            ((msg.providerId != null &&
                                    msg.providerId!.trim().isNotEmpty) ||
                                (msg.executionPath != null &&
                                    msg.executionPath!.trim().isNotEmpty) ||
                                (msg.confidenceLevel != null &&
                                    msg.confidenceLevel!.trim().isNotEmpty)))
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (msg.providerId != null &&
                                    msg.providerId!.trim().isNotEmpty)
                                  Text(
                                    'via: ${msg.providerId}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black45,
                                    ),
                                  ),
                                if (msg.executionPath != null &&
                                    msg.executionPath!.trim().isNotEmpty)
                                  Tooltip(
                                    message: _executionTooltip(
                                      msg.executionPath!,
                                      reason: msg.executionReason,
                                    ),
                                    child: _executionBadge(
                                      msg.executionPath!,
                                      reason: msg.executionReason,
                                    ),
                                  ),
                                if (msg.confidenceLevel != null &&
                                    msg.confidenceLevel!.trim().isNotEmpty)
                                  Tooltip(
                                    message: _confidenceTooltip(
                                      msg.confidenceLevel!,
                                      reason: msg.confidenceReason,
                                    ),
                                    child: _confidenceBadge(
                                      msg.confidenceLevel!,
                                      reason: msg.confidenceReason,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_pendingDraft != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Draf masih pending. Kamu bisa lanjut ke review kapan saja.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed:
                                  (_isLoading || _cooldownSeconds > 0)
                                      ? null
                                      : _openPendingDraft,
                              icon: const Icon(Icons.playlist_add_check),
                              label: const Text('Lanjut ke Review'),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Keluar mode draft',
                              onPressed:
                                  (_isLoading || _cooldownSeconds > 0)
                                      ? null
                                      : _exitDraftingMode,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_cooldownSeconds > 0)
                    Text(
                      'Tunggu $_cooldownSeconds detik sebelum kirim lagi.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          enabled: _cooldownSeconds <= 0,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendFromInput(),
                          decoration: const InputDecoration(
                            hintText: 'Tanya soal keuangan toko...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed:
                            (_isLoading || _cooldownSeconds > 0)
                                ? null
                                : _sendFromInput,
                        child: const Text('Kirim'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confidenceBadge(String levelRaw, {String? reason}) {
    final level = levelRaw.trim().toLowerCase();
    final palette = _confidencePalette(level);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showConfidenceInfo(level, reason: reason),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: palette.background,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border),
          ),
        ),
      ),
    );
  }

  Widget _executionBadge(String pathRaw, {String? reason}) {
    final path = pathRaw.trim().toLowerCase();
    final palette = _executionPalette(path);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showExecutionInfo(path, reason: reason),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: palette.background,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border),
          ),
        ),
      ),
    );
  }

  Future<void> _showExecutionInfo(String path, {String? reason}) async {
    final title = switch (path) {
      'local_ai' => 'Mode Hybrid (Lokal + AI)',
      'llm' => 'Mode LLM Penuh',
      _ => 'Mode Lokal',
    };
    final desc = _executionTooltip(path, reason: reason);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (context) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24 + MediaQuery.of(context).viewPadding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(desc),
              ],
            ),
          ),
    );
  }

  String _executionTooltip(String path, {String? reason}) {
    final trimmedReason = reason?.trim() ?? '';
    final suffix = trimmedReason.isEmpty ? '' : '\nDetail: $trimmedReason';
    switch (path) {
      case 'local_ai':
        return 'Indikator biru: query dieksekusi lokal, AI hanya bantu parsing/normalisasi.$suffix';
      case 'llm':
        return 'Indikator ungu: jawaban utama dirender provider AI.$suffix';
      default:
        return 'Indikator hijau-biru: jawaban dihitung/difilter langsung oleh engine lokal.$suffix';
    }
  }

  ({Color background, Color border}) _executionPalette(String path) {
    switch (path) {
      case 'local_ai':
        return (
          background: const Color(0xFFE3F2FD),
          border: const Color(0xFF90CAF9),
        );
      case 'llm':
        return (
          background: const Color(0xFFF3E5F5),
          border: const Color(0xFFCE93D8),
        );
      default:
        return (
          background: const Color(0xFFE0F2F1),
          border: const Color(0xFF80CBC4),
        );
    }
  }

  Future<void> _showConfidenceInfo(String level, {String? reason}) async {
    final title = switch (level) {
      'high' => 'Keyakinan Tinggi',
      'low' => 'Keyakinan Rendah',
      _ => 'Keyakinan Sedang',
    };
    final desc = _confidenceTooltip(level, reason: reason);
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (context) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24 + MediaQuery.of(context).viewPadding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(desc),
              ],
            ),
          ),
    );
  }

  String _confidenceTooltip(String level, {String? reason}) {
    final trimmedReason = reason?.trim() ?? '';
    final suffix = trimmedReason.isEmpty ? '' : '\nAlasan: $trimmedReason';
    switch (level) {
      case 'high':
        return 'Indikator hijau: keyakinan tinggi.$suffix';
      case 'low':
        return 'Indikator merah: keyakinan rendah.$suffix';
      default:
        return 'Indikator kuning: keyakinan sedang.$suffix';
    }
  }

  ({Color background, Color border}) _confidencePalette(String level) {
    switch (level) {
      case 'high':
        return (
          background: const Color(0xFFE8F5E9),
          border: const Color(0xFFA5D6A7),
        );
      case 'low':
        return (
          background: const Color(0xFFFFEBEE),
          border: const Color(0xFFEF9A9A),
        );
      default:
        return (
          background: const Color(0xFFFFF8E1),
          border: const Color(0xFFFFE082),
        );
    }
  }
}
