import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  bool _isLoading = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  static const List<String> _quickQuestions = [
    'Apa 2 aksi prioritas minggu ini?',
    'Kenapa laba turun di 30 hari terakhir?',
    'Produk mana yang perlu dipromosikan dulu?',
    'Bagaimana menekan pengeluaran bahan baku?',
  ];
  static const String _chatStoreKey = 'ai_chat_history_v1';
  static const String _chatSnapshotKey = 'ai_chat_snapshot_hash_v1';
  static const String _chatSavedAtKey = 'ai_chat_saved_at_v1';

  @override
  void initState() {
    super.initState();
    _loadPersistedChat();
    final initial = widget.initialQuestion?.trim();
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _sendQuestion(initial);
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
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
    _messages
      ..clear()
      ..add(
        const AiChatMessage(
          role: 'assistant',
          text:
              'Halo, saya asisten keuangan toko. Tanyakan ringkasan laba, biaya, tren produk, atau rekomendasi aksi.',
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
                if ((role != 'user' && role != 'assistant') || text.isEmpty) {
                  return null;
                }
                return AiChatMessage(role: role, text: text);
              })
              .whereType<AiChatMessage>()
              .toList();
      if (restored.isNotEmpty) {
        _messages
          ..clear()
          ..addAll(restored);
        if (mounted) {
          setState(() {});
        }
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _persistChat() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _messages
          .map((m) => {'role': m.role, 'text': m.text})
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
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(AiChatMessage(role: 'assistant', text: reply.text));
      });
      await _persistChat();
      if (!mounted) {
        return;
      }
      _startCooldown(reply.suggestedCooldownSeconds);
      _scrollToBottom();
      if (reply.actionDraft != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OcrAssistScreen(chatImportDraft: reply.actionDraft),
          ),
        );
      }
    } on AiRateLimitException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(AiChatMessage(role: 'assistant', text: error.toString()));
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
        title: const Text('Chat AI Keuangan'),
        actions: [
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
}
