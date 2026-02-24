import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  void initState() {
    super.initState();
    _resetChat();
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
    _scrollToBottom();
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Jawaban disalin ke clipboard.')),
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
      _startCooldown(reply.suggestedCooldownSeconds);
      _scrollToBottom();
    } on AiRateLimitException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(AiChatMessage(role: 'assistant', text: error.toString()));
      });
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
                        if (!isUser)
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Salin jawaban',
                              onPressed: () => _copyMessage(msg.text),
                              icon: const Icon(Icons.copy_outlined, size: 18),
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
