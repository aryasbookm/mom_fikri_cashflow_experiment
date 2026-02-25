import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_import_draft.dart';
import '../screens/ocr_assist_screen.dart';
import '../services/ai_chatbot_service.dart';
import '../services/ai_insight_service.dart';

class AiChatbotScreen extends StatefulWidget {
  const AiChatbotScreen({
    super.key,
    required this.financeSnapshot,
    this.initialQuestion,
  });

  final List<Map<String, dynamic>> financeSnapshot;
  final String? initialQuestion;

  @override
  State<AiChatbotScreen> createState() => _AiChatbotScreenState();
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
  String _chatProviderPriority = 'auto';
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
    final saved = (prefs.getString(_chatProviderPriorityKey) ?? 'auto').trim();
    final normalized =
        saved == 'gemini_first' || saved == 'groq_first' ? saved : 'auto';
    if (!mounted) {
      return;
    }
    setState(() {
      _chatProviderPriority = normalized;
    });
  }

  Future<void> _setChatProviderPriority(String value) async {
    final normalized =
        value == 'gemini_first' || value == 'groq_first' ? value : 'auto';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatProviderPriorityKey, normalized);
    if (!mounted) {
      return;
    }
    setState(() {
      _chatProviderPriority = normalized;
    });
  }

  String? _providerOrderOverride() {
    switch (_chatProviderPriority) {
      case 'groq_first':
        return 'groq,gemini';
      case 'gemini_first':
        return 'gemini,groq';
      default:
        return null;
    }
  }

  String _chatProviderPriorityLabel() {
    switch (_chatProviderPriority) {
      case 'groq_first':
        return 'Groq dulu';
      case 'gemini_first':
        return 'Gemini dulu';
      default:
        return 'Otomatis (default: Groq dulu)';
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
    final snapshotHash = prefs.getString(_chatSnapshotKey);
    final historyRaw = prefs.getString(_chatStoreKey);
    if (snapshotHash == null ||
        historyRaw == null ||
        snapshotHash != _snapshotHash()) {
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
    if (!mounted) {
      return;
    }
    setState(() {});
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

    _inputController.text = initial;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pertanyaan lanjutan sudah diisi ke kolom chat. Edit jika perlu lalu tekan Kirim.',
        ),
      ),
    );
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
            },
          )
          .toList(growable: false),
    );
    await prefs.setString(_chatStoreKey, encoded);
    await prefs.setString(_chatSnapshotKey, _snapshotHash());
    await prefs.setInt(_chatSavedAtKey, DateTime.now().millisecondsSinceEpoch);
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

  Future<void> _copyMessage(
    String text, {
    String successMessage = 'Jawaban disalin ke clipboard.',
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  void _editUserMessage(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pesan dimasukkan ke input. Edit lalu kirim ulang.'),
      ),
    );
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

    try {
      final reply = await _chatbotService.askFinancialAssistant(
        question: question,
        financeSnapshot: widget.financeSnapshot,
        history: _messages,
        providerOrderOverride: _providerOrderOverride(),
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
            ),
          );
          _pendingDraft = reply.actionDraft;
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OcrAssistScreen(chatImportDraft: draft),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingDraft = null;
      _pendingDraftMessageIndex = null;
    });
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
                    value: 'auto',
                    child: Text('Otomatis (default: Groq dulu)'),
                  ),
                  PopupMenuItem<String>(
                    value: 'groq_first',
                    child: Text('Prioritaskan Groq'),
                  ),
                  PopupMenuItem<String>(
                    value: 'gemini_first',
                    child: Text('Prioritaskan Gemini'),
                  ),
                ],
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Hapus chat',
            onPressed: _messages.length <= 1 ? null : _clearChat,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: 'Refresh data chat',
            onPressed:
                _isLoading
                    ? null
                    : () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove(_chatStoreKey);
                      await prefs.remove(_chatSnapshotKey);
                      await prefs.remove(_chatSavedAtKey);
                      if (!mounted) {
                        return;
                      }
                      setState(_resetChat);
                    },
            icon: const Icon(Icons.refresh_outlined),
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
                                              _pendingDraft = null;
                                              _pendingDraftMessageIndex = null;
                                            });
                                          },
                                  child: const Text('Edit di Chat Dulu'),
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
                                onPressed:
                                    () => _copyMessage(
                                      msg.text,
                                      successMessage:
                                          isUser
                                              ? 'Pesan disalin ke clipboard.'
                                              : 'Jawaban disalin ke clipboard.',
                                    ),
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
                        if (!isUser &&
                            ((msg.providerId != null &&
                                    msg.providerId!.trim().isNotEmpty) ||
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
                                if (msg.confidenceLevel != null &&
                                    msg.confidenceLevel!.trim().isNotEmpty)
                                  Tooltip(
                                    message:
                                        msg.confidenceReason
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true
                                            ? msg.confidenceReason!
                                            : _confidenceTooltip(
                                              msg.confidenceLevel!,
                                            ),
                                    child: _confidenceBadge(
                                      msg.confidenceLevel!,
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
                          enabled: !_isLoading && _cooldownSeconds <= 0,
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

  Widget _confidenceBadge(String levelRaw) {
    final level = levelRaw.trim().toLowerCase();
    final palette = _confidencePalette(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        _confidenceLabel(level),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: palette.foreground,
        ),
      ),
    );
  }

  String _confidenceLabel(String level) {
    switch (level) {
      case 'high':
        return 'Keyakinan: Tinggi';
      case 'low':
        return 'Keyakinan: Rendah';
      default:
        return 'Keyakinan: Sedang';
    }
  }

  String _confidenceTooltip(String level) {
    switch (level) {
      case 'high':
        return 'Jawaban cukup kuat berdasarkan data saat ini.';
      case 'low':
        return 'Jawaban bersifat perkiraan dan perlu verifikasi manual.';
      default:
        return 'Jawaban memakai sebagian asumsi/data terbatas.';
    }
  }

  ({Color background, Color border, Color foreground}) _confidencePalette(
    String level,
  ) {
    switch (level) {
      case 'high':
        return (
          background: const Color(0xFFE8F5E9),
          border: const Color(0xFFA5D6A7),
          foreground: const Color(0xFF1B5E20),
        );
      case 'low':
        return (
          background: const Color(0xFFFFEBEE),
          border: const Color(0xFFEF9A9A),
          foreground: const Color(0xFFB71C1C),
        );
      default:
        return (
          background: const Color(0xFFFFF8E1),
          border: const Color(0xFFFFE082),
          foreground: const Color(0xFFE65100),
        );
    }
  }
}
