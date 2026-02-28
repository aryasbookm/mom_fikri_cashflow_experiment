import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_import_draft.dart';
import '../models/ocr_transaction_draft.dart';
import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/product_provider.dart';
import '../services/chat_import_audit_service.dart';
import '../services/ocr_import_audit_service.dart';
import '../services/ai_insight_service.dart';
import '../services/ai_ocr_service.dart';
import '../services/ocr_learning_dictionary_service.dart';
import '../services/ai_quota_guard_service.dart';
import '../providers/transaction_provider.dart';
import 'ai_chatbot_screen.dart';

enum _OcrScanMode { fast, accurate }

class OcrAssistScreen extends StatefulWidget {
  const OcrAssistScreen({super.key, this.chatImportDraft});

  final ChatImportDraft? chatImportDraft;

  @override
  State<OcrAssistScreen> createState() => _OcrAssistScreenState();
}

class _OcrAssistScreenState extends State<OcrAssistScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = false;
  String? _imagePath;
  List<int>? _imageBytes;
  String? _imageMimeType;
  final List<_EditableDraftItem> _draftItems = [];
  final List<String> _providerTrail = [];
  final List<_ProviderAttemptLog> _providerAttemptLogs = [];
  String _detectedDate = '';
  final List<String> _notesFound = [];
  final List<String> _ignoredLines = [];
  final List<String> _inferenceNotes = [];
  bool _isPartialDayImport = false;
  bool _missingOpeningBlock = false;
  bool _missingClosingTotal = false;
  String _chatImportHash = '';
  String _ocrScanHash = '';
  String? _lastErrorMessage;
  String? _lastRejectedReason;
  bool _aiBlocked = false;
  String? _aiBlockedMessage;
  int _aiBlockedSeconds = 0;
  Timer? _quotaTimer;
  bool _isOcrLogExpanded = false;
  bool _isCompactReviewMode = true;
  _OcrScanMode _ocrScanMode = _OcrScanMode.accurate;
  final Set<int> _expandedDraftIndexes = <int>{};

  int get _selectedCount => _draftItems.where((item) => item.selected).length;
  bool get _areAllItemsSelected =>
      _draftItems.isNotEmpty && _selectedCount == _draftItems.length;
  int get _reviewCount => _draftItems.where((item) => item.needsReview).length;
  int get _missingDateCount =>
      _draftItems.where((item) => item.dateIso.trim().isEmpty).length;
  bool get _hasInferenceReviewWarning =>
      _isPartialDayImport ||
      _missingOpeningBlock ||
      _missingClosingTotal ||
      _inferenceNotes.isNotEmpty ||
      _draftItems.any((item) => item.dateSource == 'inferred');
  int get _selectedTotalAmount {
    var sum = 0;
    for (final item in _draftItems) {
      if (!item.selected) {
        continue;
      }
      sum += _parseAmountInput(item.amountController.text);
    }
    return sum;
  }

  List<int> get _detectedNoteTotals {
    final lines = <String>[..._notesFound, ..._ignoredLines];
    final candidates = <int>[];
    for (final raw in lines) {
      final line = raw.toLowerCase();
      final isTotalLine =
          line.contains('total') ||
          line.contains('jumlah') ||
          line.contains('grand total');
      final isExcluded =
          line.contains('uang bersih') ||
          line.contains('saldo') ||
          line.contains('modal');
      if (!isTotalLine || isExcluded) {
        continue;
      }
      final values = _extractAmountCandidates(raw);
      candidates.addAll(values.where((v) => v > 0));
    }
    candidates.sort();
    return candidates;
  }

  List<int> _extractAmountCandidates(String text) {
    final matches =
        RegExp(
          r'\d[\d\.\,\s]{1,}',
        ).allMatches(text).map((m) => m.group(0) ?? '').toList();
    final values = <int>[];
    for (final raw in matches) {
      final parsed = _parseAmountInput(raw);
      if (parsed > 0) {
        values.add(parsed);
      }
    }
    return values;
  }

  Map<String, int> _selectedTotalsByDate() {
    final map = <String, int>{};
    for (final item in _draftItems) {
      if (!item.selected) {
        continue;
      }
      final key = _dateKey(item.dateIso);
      map[key] =
          (map[key] ?? 0) + _parseAmountInput(item.amountController.text);
    }
    return map;
  }

  Map<String, int> _persistedTotalsByDate(TransactionProvider provider) {
    final map = <String, int>{};
    for (final tx in provider.transactions) {
      if (tx.type == 'WASTE') {
        continue;
      }
      final parsed = DateTime.tryParse(tx.date);
      if (parsed == null) {
        continue;
      }
      final key = _toDateIso(parsed);
      map[key] = (map[key] ?? 0) + tx.amount;
    }
    return map;
  }

  int? _resolveNoteTotalForSegment({
    required int groupCount,
    required int segmentIndex,
    required List<int> noteTotals,
  }) {
    if (noteTotals.isEmpty) {
      return null;
    }
    if (groupCount == 1) {
      return noteTotals.last;
    }
    if (noteTotals.length == groupCount && segmentIndex < noteTotals.length) {
      return noteTotals[segmentIndex];
    }
    return null;
  }

  Widget _buildDateGroupSummaryCard({
    required NumberFormat currency,
    required String dateIso,
    required int scanTotal,
    required int persistedTotal,
    required int? noteTotal,
  }) {
    final cumulative = scanTotal + persistedTotal;
    final canValidate = noteTotal != null && dateIso.trim().isNotEmpty;
    final isMismatch = canValidate && noteTotal != cumulative;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            isMismatch
                ? const Color(0xFFFFEBEE)
                : canValidate
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              isMismatch
                  ? const Color(0xFFFFCDD2)
                  : canValidate
                  ? const Color(0xFFC8E6C9)
                  : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Scan: ${currency.format(scanTotal)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'Total Kumulatif Tanggal (DB + Scan): ${currency.format(cumulative)}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (noteTotal != null) ...[
            const SizedBox(height: 2),
            Text(
              'Total Catatan: ${currency.format(noteTotal)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            canValidate
                ? (isMismatch
                    ? 'Selisih terdeteksi. Mohon cek nominal di grup tanggal ini.'
                    : 'Cocok dengan total catatan.')
                : 'Belum bisa divalidasi (total catatan per tanggal tidak jelas).',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  canValidate
                      ? (isMismatch
                          ? const Color(0xFFB71C1C)
                          : const Color(0xFF1B5E20))
                      : const Color(0xFF8A6D1A),
            ),
          ),
        ],
      ),
    );
  }

  String _providerLabel(String providerId) {
    switch (providerId) {
      case 'groq':
        return 'groq';
      case 'chat-import':
        return 'chat-import';
      default:
        return providerId;
    }
  }

  String _providerStageLabel(String stage) {
    final normalized = stage.trim();
    if (normalized.startsWith('text_structuring_pass:')) {
      final model = normalized.substring('text_structuring_pass:'.length);
      return 'text_structuring_pass ($model)';
    }
    return normalized;
  }

  void _recordProviderEvent(
    String providerId,
    String status,
    String? detail, [
    String? stage,
  ]) {
    final now = DateTime.now();
    if (status == 'try') {
      _providerAttemptLogs.add(
        _ProviderAttemptLog(
          providerId: providerId,
          stage: stage,
          status: status,
          detail: detail,
          startedAt: now,
        ),
      );
      return;
    }
    for (var i = _providerAttemptLogs.length - 1; i >= 0; i--) {
      final log = _providerAttemptLogs[i];
      if (log.providerId == providerId &&
          log.stage == stage &&
          log.status == 'try') {
        _providerAttemptLogs[i] = log.copyWith(
          status: status,
          detail: detail,
          elapsedMs: now.difference(log.startedAt).inMilliseconds,
        );
        return;
      }
    }
    _providerAttemptLogs.add(
      _ProviderAttemptLog(
        providerId: providerId,
        stage: stage,
        status: status,
        detail: detail,
        startedAt: now,
      ),
    );
  }

  String _providerStatusLabel(_ProviderAttemptLog log) {
    switch (log.status) {
      case 'ok':
        return 'Success';
      case 'rate_limit':
        return 'Failed (429)';
      case 'temporary':
        return 'Failed (Temporary)';
      case 'skipped':
        return 'Skipped';
      case 'error':
        return 'Failed';
      case 'try':
        return 'Trying...';
      default:
        return log.status;
    }
  }

  String _providerDetailLabel(_ProviderAttemptLog log) {
    final detail = (log.detail ?? '').trim();
    if (detail.isEmpty) {
      return '-';
    }
    if (detail.contains('429')) {
      return 'Error 429: Quota/Rate limit.';
    }
    if (detail.contains('404')) {
      return 'Error 404: Model tidak ditemukan/tidak tersedia.';
    }
    if (detail.contains('401') || detail.contains('403')) {
      return 'Auth error: akses key/model ditolak.';
    }
    if (detail.toLowerCase().contains('socket') ||
        detail.toLowerCase().contains('connection') ||
        detail.toLowerCase().contains('timed out')) {
      return 'Network error.';
    }
    if (detail.length > 120) {
      return '${detail.substring(0, 120)}...';
    }
    return detail;
  }

  @override
  void initState() {
    super.initState();
    _applyChatImportDraftIfAny();
    _refreshAiQuotaState();
  }

  void _applyChatImportDraftIfAny() {
    final draft = widget.chatImportDraft;
    if (draft == null || draft.transactions.isEmpty) {
      return;
    }
    setState(() {
      _clearDraftItems();
      _draftItems.addAll(
        draft.transactions.map(
          (item) => _EditableDraftItem(
            selected: true,
            type: item.type,
            amount: item.amount,
            description: item.description,
            originalDescription: item.description,
            categoryHint: item.categoryHint,
            dateIso: item.dateIso,
            dateSource: item.dateSource,
            confidence: item.confidence,
            rawText: item.description,
            needsReview: item.needsReview,
            warning: item.warning,
          ),
        ),
      );
      _detectedDate = draft.transactions
          .map((item) => item.dateIso.trim())
          .firstWhere((d) => d.isNotEmpty, orElse: () => '');
      _notesFound
        ..clear()
        ..addAll(draft.notesFound);
      _ignoredLines
        ..clear()
        ..addAll(draft.ignoredLines);
      _inferenceNotes
        ..clear()
        ..addAll(draft.inferenceNotes);
      _isPartialDayImport = draft.isPartialDay;
      _missingOpeningBlock = draft.missingOpeningBlock;
      _missingClosingTotal = draft.missingClosingTotal;
      _providerTrail
        ..clear()
        ..add('chat-import');
      _chatImportHash = draft.importHash.trim();
      _ocrScanHash = '';
      _lastErrorMessage = null;
      _lastRejectedReason = null;
      _isLoading = false;
      _applyMajorityTypeDefault();
    });
  }

  Future<void> _refreshAiQuotaState() async {
    final state = await AiQuotaGuardService.getState();
    if (!mounted) {
      return;
    }
    setState(() {
      _aiBlocked = state.isBlocked;
      _aiBlockedMessage = state.isBlocked ? state.message : null;
      _aiBlockedSeconds = state.retryAfterSeconds;
    });
    _startQuotaTimerIfNeeded();
  }

  void _startQuotaTimerIfNeeded() {
    _quotaTimer?.cancel();
    if (!_aiBlocked || _aiBlockedSeconds <= 0) {
      return;
    }
    _quotaTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_aiBlockedSeconds <= 1) {
        timer.cancel();
        await _refreshAiQuotaState();
        return;
      }
      setState(() {
        _aiBlockedSeconds -= 1;
        _aiBlockedMessage =
            'AI sedang istirahat. Coba lagi dalam $_aiBlockedSeconds detik.';
      });
    });
  }

  String _toUserFacingOcrError(Object error) {
    final rawText = error.toString().trim();
    final raw = rawText.toLowerCase();
    if (raw.contains('internet') || raw.contains('socket')) {
      return 'Tidak ada koneksi internet. Coba lagi.';
    }
    if (raw.contains('timeout')) {
      return 'Proses scan AI timeout. Coba lagi.';
    }
    if (raw.contains('503') || raw.contains('server')) {
      return 'Server AI sedang sibuk. Coba lagi sebentar.';
    }
    if (raw.contains('bukan catatan transaksi')) {
      return 'Foto ini bukan catatan transaksi yang jelas.';
    }
    if (raw.contains('api key')) {
      return 'Konfigurasi AI belum siap. Hubungi admin aplikasi.';
    }
    if (raw.contains('akses ocr ai ditolak') || raw.contains('403')) {
      return 'Akses OCR ditolak. Periksa API key atau kuota.';
    }
    if (raw.contains('model ocr ai tidak ditemukan') || raw.contains('404')) {
      return 'Model OCR tidak tersedia. Periksa konfigurasi model.';
    }
    if (raw.contains('format transaksi yang valid') ||
        raw.contains('data ocr yang tidak terbaca') ||
        raw.contains('tidak mengembalikan data ocr')) {
      return 'AI merespons, tetapi formatnya tidak bisa dipakai sebagai draft transaksi. Coba foto lebih jelas.';
    }
    if (raw.contains('format json ocr ai tidak valid')) {
      return 'AI merespons, tapi format JSON tidak valid. Tekan "Coba Lagi".';
    }
    if (raw.contains('terpotong') || raw.contains('tidak lengkap')) {
      return 'Respons AI belum lengkap. Tekan "Coba Lagi".';
    }

    final cleaned =
        rawText.startsWith('Exception:')
            ? rawText.substring(10).trim()
            : rawText;
    if (cleaned.isNotEmpty) {
      return cleaned;
    }
    return 'Gagal memproses scan. Coba lagi.';
  }

  Future<void> _pickAndProcess(ImageSource source) async {
    if (_isLoading) {
      return;
    }
    if (_aiBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _aiBlockedMessage ?? 'Fitur AI sedang tidak tersedia saat ini.',
          ),
        ),
      );
      return;
    }

    final file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (file == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _imagePath = file.path;
      _imageBytes = null;
      _imageMimeType = null;
      _clearDraftItems();
      _providerTrail.clear();
      _providerAttemptLogs.clear();
      _chatImportHash = '';
      _ocrScanHash = '';
      _detectedDate = '';
      _notesFound.clear();
      _ignoredLines.clear();
      _inferenceNotes.clear();
      _isPartialDayImport = false;
      _missingOpeningBlock = false;
      _missingClosingTotal = false;
      _lastErrorMessage = null;
      _lastRejectedReason = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final mimeType = _detectMimeType(file.path);
      if (mimeType == null) {
        throw Exception(
          'Format foto dari galeri belum didukung. Gunakan JPG/PNG/WEBP atau kirim ulang sebagai JPG.',
        );
      }
      setState(() {
        _imageBytes = bytes;
        _imageMimeType = mimeType;
      });
      await _processCurrentImage();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _lastErrorMessage = _toUserFacingOcrError(error);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_lastErrorMessage!)));
    }
  }

  Future<void> _processCurrentImage() async {
    final bytes = _imageBytes;
    final mimeType = _imageMimeType;
    if (bytes == null || mimeType == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _lastErrorMessage = null;
      _providerTrail.clear();
      _providerAttemptLogs.clear();
    });

    try {
      final batch = await AiOcrService().extractDraftFromImageBytes(
        imageBytes: bytes,
        mimeType: mimeType,
        providerOrderOverride: 'gemini,groq',
        geminiOcrModelChainOverride: _geminiOcrChainForSelectedMode(),
        onProviderEvent: (providerId, status, detail, [stage]) {
          if (!mounted) {
            return;
          }
          setState(() {
            if (status == 'try' && !_providerTrail.contains(providerId)) {
              _providerTrail.add(providerId);
            }
            _recordProviderEvent(providerId, status, detail, stage);
          });
        },
      );
      final detectedDateIso = _normalizeDetectedDateIso(batch.detectedDate);
      final fallbackTodayIso = _toDateIso(DateTime.now());
      await OcrLearningDictionaryService.preloadFromProductsIfNeeded();
      final dictionary = await OcrLearningDictionaryService.getDictionary();
      final editableItems =
          batch.transactions.map((item) {
            final correctedDescription =
                OcrLearningDictionaryService.applyCorrection(
                  item.description,
                  dictionary,
                );
            final hasItemDate = item.dateIso.trim().isNotEmpty;
            final resolvedDateIso =
                hasItemDate
                    ? item.dateIso
                    : (detectedDateIso ?? fallbackTodayIso);
            final isDateInferred = !hasItemDate;
            final inferredDateWarning =
                detectedDateIso != null
                    ? 'Tanggal diisi dari tanggal terdeteksi, mohon cek ulang.'
                    : 'Tanggal tidak terdeteksi, otomatis diisi tanggal hari ini. Mohon cek ulang.';

            return _EditableDraftItem(
              selected: true,
              type: item.type,
              amount: item.amount,
              description: correctedDescription,
              originalDescription: item.description,
              categoryHint: item.categoryHint,
              dateIso: resolvedDateIso,
              dateSource: isDateInferred ? 'inferred' : item.dateSource,
              confidence: item.confidence,
              rawText: item.rawText,
              needsReview: item.needsReview || isDateInferred,
              warning:
                  isDateInferred
                      ? _mergeWarning(item.warning, inferredDateWarning)
                      : item.warning,
            );
          }).toList();
      if (_ocrScanMode == _OcrScanMode.accurate) {
        final draft = _buildChatImportDraftFromBatch(
          batch: batch,
          editableItems: editableItems,
          fallbackDateIso: fallbackTodayIso,
          imageBytes: bytes,
          mimeType: mimeType,
        );
        if (draft.transactions.isEmpty) {
          throw Exception(
            'OCR mode akurat belum menemukan baris transaksi yang valid. Coba scan ulang atau gunakan Mode Cepat.',
          );
        }
        final auditText = _buildRawOcrAuditText(batch);
        final financeSnapshot = _buildFinanceSnapshotForChat(
          transactionProvider: context.read<TransactionProvider>(),
          productProvider: context.read<ProductProvider>(),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _clearDraftItems();
          _detectedDate = batch.detectedDate;
          _notesFound
            ..clear()
            ..addAll(batch.notesFound);
          _ignoredLines
            ..clear()
            ..addAll(batch.ignoredLines);
          _inferenceNotes.clear();
          _isPartialDayImport = false;
          _missingOpeningBlock = false;
          _missingClosingTotal = false;
          _chatImportHash = '';
          _ocrScanHash = _buildOcrScanHash(
            imageBytes: bytes,
            mimeType: mimeType,
          );
          _lastErrorMessage = null;
          _lastRejectedReason = null;
        });
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder:
                (_) => AiChatbotScreen(
                  financeSnapshot: financeSnapshot,
                  initialDraft: draft,
                  initialDraftAuditText: auditText,
                ),
          ),
        );
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _clearDraftItems();
        _draftItems.addAll(editableItems);
        _applyMajorityTypeDefault();
        _detectedDate = batch.detectedDate;
        _notesFound
          ..clear()
          ..addAll(batch.notesFound);
        _ignoredLines
          ..clear()
          ..addAll(batch.ignoredLines);
        _inferenceNotes.clear();
        _isPartialDayImport = false;
        _missingOpeningBlock = false;
        _missingClosingTotal = false;
        _chatImportHash = '';
        _ocrScanHash = _buildOcrScanHash(imageBytes: bytes, mimeType: mimeType);
        _lastErrorMessage = null;
        _lastRejectedReason = null;
      });
    } on AiRateLimitException catch (error) {
      await AiQuotaGuardService.recordRateLimit(error);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastErrorMessage = error.toString();
      });
      await _refreshAiQuotaState();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_lastErrorMessage!)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastErrorMessage = _toUserFacingOcrError(error);
        _lastRejectedReason =
            _lastErrorMessage!.toLowerCase().contains('bukan catatan transaksi')
                ? _lastErrorMessage
                : null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_lastErrorMessage!)));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmAndRescanCurrentImage() async {
    if (_imageBytes == null || _imageMimeType == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Scan Ulang Foto'),
            content: const Text('Gunakan foto yang sama untuk scan ulang OCR?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Ya, Scan Ulang'),
              ),
            ],
          ),
    );
    if (confirmed == true && mounted) {
      await _processCurrentImage();
    }
  }

  String? _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return null;
    }
    return 'image/jpeg';
  }

  int? _resolveCategoryId({
    required CategoryProvider categoryProvider,
    required String type,
    required String hint,
  }) {
    final categories =
        type == 'IN'
            ? categoryProvider.incomeCategories
            : categoryProvider.expenseCategories;
    final valid = categories.where((cat) => cat.id != null).toList();
    if (valid.isEmpty) {
      return null;
    }

    final normalizedHint = hint.toLowerCase().trim();
    if (normalizedHint.isNotEmpty) {
      for (final category in valid) {
        if (category.name.toLowerCase().trim() == normalizedHint) {
          return category.id;
        }
      }
      for (final category in valid) {
        final name = category.name.toLowerCase().trim();
        if (name.contains(normalizedHint) || normalizedHint.contains(name)) {
          return category.id;
        }
      }
    }
    return valid.first.id;
  }

  Future<void> _saveSelectedDrafts() async {
    if (_isLoading) {
      return;
    }
    final selected = _draftItems.where((item) => item.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih minimal 1 transaksi untuk disimpan.'),
        ),
      );
      return;
    }

    final invalidItems = <String>[];
    for (final item in selected) {
      final amount = _parseAmountInput(item.amountController.text);
      final description = item.descriptionController.text.trim();
      if (item.type != 'IN' && item.type != 'OUT') {
        invalidItems.add('Tipe transaksi belum valid.');
        continue;
      }
      if (amount <= 0) {
        invalidItems.add(
          'Nominal tidak valid pada item "${description.isEmpty ? '-' : description}".',
        );
      }
      if (description.length < 3) {
        invalidItems.add(
          'Keterangan terlalu singkat pada item "$description".',
        );
      }
    }
    if (invalidItems.isNotEmpty && mounted) {
      final preview = invalidItems.take(4).join('\n- ');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Data Belum Bisa Disimpan'),
            content: Text(
              'Perbaiki data berikut sebelum simpan:\n- $preview'
              '${invalidItems.length > 4 ? '\n- ...dan ${invalidItems.length - 4} item lainnya' : ''}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Oke, Perbaiki Dulu'),
              ),
            ],
          );
        },
      );
      return;
    }

    if (_providerTrail.contains('chat-import')) {
      final duplicate = await ChatImportAuditService.findRecentDuplicate(
        _chatImportHash,
      );
      if (duplicate != null && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Draf Mirip Terdeteksi'),
                content: Text(
                  'Draf chat import dengan hash yang sama terdeteksi pernah disimpan pada '
                  '${DateFormat('d MMM y HH:mm', 'id_ID').format(duplicate.savedAt)} '
                  '(${duplicate.itemCount} transaksi). Lanjut simpan ulang?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Batal'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Lanjut Simpan'),
                  ),
                ],
              ),
        );
        if (!mounted || proceed != true) {
          return;
        }
      }
    } else {
      final duplicate = await OcrImportAuditService.findRecentDuplicate(
        _ocrScanHash,
      );
      if (duplicate != null && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Scan Mirip Terdeteksi'),
                content: Text(
                  'Hasil OCR dengan hash gambar yang sama terdeteksi pernah disimpan pada '
                  '${DateFormat('d MMM y HH:mm', 'id_ID').format(duplicate.savedAt)} '
                  '(${duplicate.itemCount} transaksi). Lanjut simpan ulang?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Batal'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Lanjut Simpan'),
                  ),
                ],
              ),
        );
        if (!mounted || proceed != true) {
          return;
        }
      }
    }
    if (!mounted) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Konfirmasi Simpan'),
            content: Text(
              'Simpan $_selectedCount transaksi dari hasil scan ini?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Simpan'),
              ),
            ],
          ),
    );
    if (!mounted || confirm != true) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final auth = context.read<AuthProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final transactionProvider = context.read<TransactionProvider>();

    final userId = auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User belum login.')));
      return;
    }

    await categoryProvider.loadCategories();

    var success = 0;
    var failed = 0;
    var savedAmountTotal = 0;
    final savedTransactions = <TransactionModel>[];
    final learningPairs = <String, String>{};
    for (final item in selected) {
      final amount = _parseAmountInput(item.amountController.text);
      final description = item.descriptionController.text.trim();
      if (amount <= 0 || description.length < 3) {
        failed += 1;
        continue;
      }

      final auditedDescription = _applyAuditTag(description);

      final categoryId = _resolveCategoryId(
        categoryProvider: categoryProvider,
        type: item.type,
        hint: item.categoryHint,
      );
      if (categoryId == null) {
        failed += 1;
        continue;
      }

      final parsedDate =
          item.dateIso.trim().isNotEmpty
              ? DateTime.tryParse(item.dateIso)
              : null;
      final now = DateTime.now();
      final txDateValue = DateTime(
        parsedDate?.year ?? now.year,
        parsedDate?.month ?? now.month,
        parsedDate?.day ?? now.day,
        now.hour,
        now.minute,
        now.second,
      );

      try {
        final created = TransactionModel(
          type: item.type,
          amount: amount,
          categoryId: categoryId,
          description: auditedDescription,
          date: txDateValue.toIso8601String(),
          userId: userId,
        );
        final insertedId = await transactionProvider.addTransaction(created);
        success += 1;
        savedAmountTotal += amount;
        savedTransactions.add(
          TransactionModel(
            id: insertedId,
            type: created.type,
            amount: created.amount,
            categoryId: created.categoryId,
            description: created.description,
            date: created.date,
            userId: created.userId,
            categoryName: created.categoryName,
            productId: created.productId,
            quantity: created.quantity,
          ),
        );
        if (item.originalDescription.trim().isNotEmpty &&
            description.isNotEmpty &&
            item.originalDescription.trim() != description) {
          learningPairs[item.originalDescription.trim()] = description;
        }
      } catch (_) {
        failed += 1;
      }
    }

    if (success > 0 && learningPairs.isNotEmpty) {
      await OcrLearningDictionaryService.learnFromEdits(learningPairs);
    }
    if (success > 0 && _providerTrail.contains('chat-import')) {
      await ChatImportAuditService.recordSaved(
        hash: _chatImportHash,
        itemCount: success,
        totalAmount: savedAmountTotal,
      );
    } else if (success > 0) {
      await OcrImportAuditService.recordSaved(
        hash: _ocrScanHash,
        itemCount: success,
        totalAmount: savedAmountTotal,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });

    final sourceLabel =
        _providerTrail.contains('chat-import') ? 'chat import' : 'scan OCR';
    final message =
        success <= 0
            ? 'Tidak ada transaksi yang berhasil disimpan. Periksa data lalu coba lagi.'
            : failed == 0
            ? 'Berhasil menyimpan $success transaksi dari $sourceLabel.'
            : 'Selesai: berhasil $success, gagal $failed. Kamu bisa urungkan transaksi yang berhasil disimpan.';
    final shouldPopAfterSave = success > 0 && failed == 0;
    final messenger = ScaffoldMessenger.of(context);
    if (success > 0) {
      _showUndoSaveSnackBar(
        messenger: messenger,
        transactionProvider: transactionProvider,
        auth: auth,
        savedTransactions: savedTransactions,
        message: message,
      );
    } else {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }

    if (shouldPopAfterSave) {
      final saveResult = <String, dynamic>{
        'saved': true,
        'source':
            _providerTrail.contains('chat-import') ? 'chat-import' : 'ocr',
        'success_count': success,
        'failed_count': failed,
      };
      _clearDraftItems();
      _detectedDate = '';
      _notesFound.clear();
      _ignoredLines.clear();
      if (mounted) {
        Navigator.of(context).pop(saveResult);
      }
    }
  }

  void _selectAll(bool selected) {
    setState(() {
      for (final item in _draftItems) {
        item.selected = selected;
      }
    });
  }

  void _setAllType(String type) {
    final isChatImport = _providerTrail.contains('chat-import');
    setState(() {
      for (final item in _draftItems) {
        if (isChatImport && !_shouldBulkApplyTypeOnChatImport(item)) {
          continue;
        }
        item.type = type;
      }
    });
  }

  int _countBulkTypeTargets(String type) {
    final isChatImport = _providerTrail.contains('chat-import');
    var count = 0;
    for (final item in _draftItems) {
      if (isChatImport && !_shouldBulkApplyTypeOnChatImport(item)) {
        continue;
      }
      if (item.type != type) {
        count += 1;
      }
    }
    return count;
  }

  String _nextBulkType() {
    final isChatImport = _providerTrail.contains('chat-import');
    final applicable = <_EditableDraftItem>[];
    for (final item in _draftItems) {
      if (isChatImport && !_shouldBulkApplyTypeOnChatImport(item)) {
        continue;
      }
      applicable.add(item);
    }
    if (applicable.isEmpty) {
      return 'IN';
    }
    final allIn = applicable.every((item) => item.type == 'IN');
    return allIn ? 'OUT' : 'IN';
  }

  void _toggleSelectAll() {
    _selectAll(!_areAllItemsSelected);
  }

  void _toggleCompactMode() {
    setState(() {
      _isCompactReviewMode = !_isCompactReviewMode;
      if (!_isCompactReviewMode) {
        _expandedDraftIndexes.clear();
      }
    });
  }

  Future<void> _confirmAndApplyBulkTypeToggle() async {
    final nextType = _nextBulkType();
    final targetCount = _countBulkTypeTargets(nextType);
    if (targetCount == 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada item yang perlu diubah.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Konfirmasi Ubah Tipe'),
            content: Text('Ubah $targetCount item menjadi $nextType?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Ya, Terapkan'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      _setAllType(nextType);
    }
  }

  Widget _buildMassActionBar() {
    final nextSelectionLabel =
        _areAllItemsSelected ? 'Batal Pilih' : 'Pilih Semua';
    final nextSelectionIcon =
        _areAllItemsSelected ? Icons.remove_done : Icons.done_all;
    final nextDisplayLabel =
        _isCompactReviewMode ? 'Lihat Detail' : 'Tampilan Ringkas';
    final nextDisplayIcon =
        _isCompactReviewMode ? Icons.unfold_more : Icons.unfold_less;
    final nextBulkType = _nextBulkType();
    final nextBulkLabel = nextBulkType == 'IN' ? 'Semua MASUK' : 'Semua KELUAR';
    final nextBulkIcon =
        nextBulkType == 'IN' ? Icons.north_east : Icons.south_east;
    final nextBulkForegroundColor =
        nextBulkType == 'IN'
            ? const Color(0xFF166534)
            : const Color(0xFFB91C1C);
    final nextBulkBackgroundColor =
        nextBulkType == 'IN'
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFFEE2E2);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _toggleSelectAll,
          icon: Icon(nextSelectionIcon),
          label: Text(nextSelectionLabel),
        ),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _toggleCompactMode,
          icon: Icon(nextDisplayIcon),
          label: Text(nextDisplayLabel),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            foregroundColor: nextBulkForegroundColor,
            backgroundColor: nextBulkBackgroundColor,
          ),
          onPressed: _isLoading ? null : _confirmAndApplyBulkTypeToggle,
          icon: Icon(nextBulkIcon),
          label: Text(nextBulkLabel),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Dipilih: $_selectedCount'),
        ),
      ],
    );
  }

  void _clearDraftItems() {
    for (final item in _draftItems) {
      item.dispose();
    }
    _draftItems.clear();
    _expandedDraftIndexes.clear();
  }

  void _applyMajorityTypeDefault() {
    if (_draftItems.isEmpty) {
      return;
    }
    var predictedInCount = 0;
    var predictedOutCount = 0;
    var productLikeCount = 0;
    var strongExpenseCount = 0;
    final signals = <_TypeSignal>[];

    for (final item in _draftItems) {
      final signal = _buildTypeSignal(item);
      signals.add(signal);
      if (signal.predictedType == 'OUT') {
        predictedOutCount += 1;
      } else {
        predictedInCount += 1;
      }
      if (_looksLikeProductLine(item)) {
        productLikeCount += 1;
      }
      if (signal.strongOut) {
        strongExpenseCount += 1;
      }
    }

    final total = _draftItems.length;
    final productHeavyThreshold = (total * 0.6).ceil();
    String? majorityType;
    if (productLikeCount >= productHeavyThreshold &&
        strongExpenseCount <= (total * 0.2).floor()) {
      majorityType = 'IN';
    } else {
      final dominant =
          predictedInCount > predictedOutCount
              ? predictedInCount
              : predictedOutCount;
      if (dominant / total >= 0.55) {
        majorityType = predictedInCount >= predictedOutCount ? 'IN' : 'OUT';
      }
    }
    if (majorityType == null) {
      return;
    }

    final isChatImport = _providerTrail.contains('chat-import');
    for (var i = 0; i < _draftItems.length; i++) {
      final item = _draftItems[i];
      if (isChatImport && !_shouldBulkApplyTypeOnChatImport(item)) {
        continue;
      }
      final signal = signals[i];
      final stronglyOpposesMajority =
          (majorityType == 'IN' && signal.strongOut) ||
          (majorityType == 'OUT' && signal.strongIn);
      if (stronglyOpposesMajority) {
        continue;
      }
      item.type = majorityType;
    }
  }

  _TypeSignal _buildTypeSignal(_EditableDraftItem item) {
    final hint = item.categoryHint.toLowerCase().trim();
    final desc = item.descriptionController.text.toLowerCase().trim();
    var inScore = 0;
    var outScore = 0;

    const strongOutKeywords = <String>[
      'bahan baku',
      'operasional',
      'gaji',
      'utang',
      'prive',
      'pengeluaran',
      'listrik',
      'token',
      'pulsa',
      'beli',
      'bayar',
      'sewa',
      'bbm',
      'bensin',
      'gas',
      'air',
      'alat',
      'kemasan',
      'tepung',
      'telur',
      'mentega',
      'gula',
    ];
    const strongInKeywords = <String>[
      'penjualan',
      'pemasukan',
      'income',
      'jual',
      'produk',
      'kue',
      'snack',
      'minuman',
      'order',
      'laku',
    ];

    for (final keyword in strongOutKeywords) {
      if (hint.contains(keyword)) {
        outScore += 3;
      }
      if (desc.contains(keyword)) {
        outScore += 2;
      }
    }
    for (final keyword in strongInKeywords) {
      if (hint.contains(keyword)) {
        inScore += 3;
      }
      if (desc.contains(keyword)) {
        inScore += 2;
      }
    }
    if (_looksLikeProductLine(item)) {
      inScore += 2;
    }
    if (RegExp(r'\d+\s*x\s*\d+').hasMatch(desc)) {
      inScore += 1;
    }

    final predictedType =
        outScore > inScore
            ? 'OUT'
            : inScore > outScore
            ? 'IN'
            : item.type;
    return _TypeSignal(
      predictedType: predictedType,
      strongOut: outScore >= inScore + 2,
      strongIn: inScore >= outScore + 2,
    );
  }

  String _geminiOcrChainForSelectedMode() {
    switch (_ocrScanMode) {
      case _OcrScanMode.fast:
        return 'gemini-2.5-flash-lite';
      case _OcrScanMode.accurate:
        return 'gemini-3.1-pro-preview,gemini-3-flash-preview,gemini-2.5-flash';
    }
  }

  ChatImportDraft _buildChatImportDraftFromBatch({
    required OcrBatchDraft batch,
    required List<_EditableDraftItem> editableItems,
    required String fallbackDateIso,
    required List<int> imageBytes,
    required String mimeType,
  }) {
    final confidenceAvg =
        editableItems.isEmpty
            ? 0
            : editableItems
                    .map((item) => item.confidence.clamp(0, 100))
                    .reduce((a, b) => a + b) ~/
                editableItems.length;
    final importHash = _buildOcrScanHash(
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
    return ChatImportDraft(
      intent: 'import_transactions_draft',
      source: 'ocr-accurate-chat',
      importHash: importHash,
      transactions: editableItems
          .map(
            (item) => ChatImportDraftItem(
              type: item.type,
              amount: _parseAmountInput(item.amountController.text),
              description: item.descriptionController.text.trim(),
              categoryHint: item.categoryHint,
              dateIso:
                  item.dateIso.trim().isEmpty
                      ? fallbackDateIso
                      : item.dateIso.trim(),
              dateSource:
                  item.dateSource.trim().isEmpty
                      ? 'inferred'
                      : item.dateSource.trim(),
              needsReview: item.needsReview,
              warning: item.warning,
              confidence: item.confidence.clamp(0, 100),
            ),
          )
          .toList(growable: false),
      notesFound: List<String>.from(batch.notesFound),
      ignoredLines: List<String>.from(batch.ignoredLines),
      confidence: confidenceAvg.clamp(0, 100),
      isPartialDay: false,
      missingOpeningBlock: false,
      missingClosingTotal: false,
      inferenceNotes: const <String>[
        'Draft berasal dari OCR Mode Akurat dan perlu review sebelum simpan.',
      ],
    );
  }

  String _buildRawOcrAuditText(OcrBatchDraft batch) {
    final lines = <String>[];
    if (batch.detectedDate.trim().isNotEmpty) {
      lines.add('Tanggal terdeteksi: ${batch.detectedDate.trim()}');
    } else {
      lines.add('Tanggal terdeteksi: (tidak ada, fallback ke hari ini).');
    }
    final rawCandidates =
        batch.transactions
            .map((item) => item.rawText.trim())
            .where((text) => text.isNotEmpty)
            .take(20)
            .toList();
    if (rawCandidates.isNotEmpty) {
      lines.add('Baris OCR mentah:');
      lines.addAll(rawCandidates.map((line) => '- $line'));
    }
    if (batch.notesFound.isNotEmpty) {
      lines.add('Catatan non-transaksi:');
      lines.addAll(batch.notesFound.take(8).map((line) => '- $line'));
    }
    if (batch.ignoredLines.isNotEmpty) {
      lines.add('Baris diabaikan:');
      lines.addAll(batch.ignoredLines.take(8).map((line) => '- $line'));
    }
    return lines.join('\n');
  }

  List<Map<String, dynamic>> _buildFinanceSnapshotForChat({
    required TransactionProvider transactionProvider,
    required ProductProvider productProvider,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final periodStart = today.subtract(const Duration(days: 29));
    var income30 = 0;
    var expense30 = 0;
    final daily = <String, Map<String, dynamic>>{};
    final incomeCategories = <String, int>{};
    final expenseCategories = <String, int>{};

    for (final tx in transactionProvider.transactions) {
      final parsed = DateTime.tryParse(tx.date);
      if (parsed == null || parsed.isBefore(periodStart)) {
        continue;
      }
      final dayKey = DateFormat('yyyy-MM-dd').format(parsed);
      final row =
          daily[dayKey] ??
          <String, dynamic>{
            'type': 'daily_summary',
            'date': dayKey,
            'income': 0,
            'expense': 0,
          };
      final categoryName = (tx.categoryName ?? 'Tanpa Kategori').trim();
      if (tx.type == 'IN') {
        income30 += tx.amount;
        row['income'] = (row['income'] as int) + tx.amount;
        incomeCategories[categoryName] =
            (incomeCategories[categoryName] ?? 0) + tx.amount;
      } else if (tx.type == 'OUT') {
        expense30 += tx.amount;
        row['expense'] = (row['expense'] as int) + tx.amount;
        expenseCategories[categoryName] =
            (expenseCategories[categoryName] ?? 0) + tx.amount;
      }
      daily[dayKey] = row;
    }

    final snapshot = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'summary_30_days',
        'income': income30,
        'expense': expense30,
        'net': income30 - expense30,
      },
    ];

    final dailyRows =
        daily.values.toList()..sort(
          (a, b) => (a['date'] as String).compareTo((b['date'] as String)),
        );
    snapshot.addAll(dailyRows);

    snapshot.addAll(
      incomeCategories.entries
          .map(
            (entry) => <String, dynamic>{
              'type': 'income_category_30d',
              'category': entry.key,
              'total_amount': entry.value,
            },
          )
          .toList(growable: false),
    );
    snapshot.addAll(
      expenseCategories.entries
          .map(
            (entry) => <String, dynamic>{
              'type': 'expense_category_30d',
              'category': entry.key,
              'total_amount': entry.value,
            },
          )
          .toList(growable: false),
    );

    snapshot.addAll(
      productProvider.products
          .take(100)
          .map(
            (product) => <String, dynamic>{
              'type': 'product_catalog',
              'name': product.name,
              'stock_now': product.stock,
              'min_stock': product.minStock,
              'is_active': product.isActive,
            },
          )
          .toList(growable: false),
    );
    return snapshot;
  }

  String _mergeWarning(String base, String extra) {
    final b = base.trim();
    final e = extra.trim();
    if (b.isEmpty) {
      return e;
    }
    if (e.isEmpty || b.toLowerCase().contains(e.toLowerCase())) {
      return b;
    }
    return '$b $e';
  }

  String? _normalizeDetectedDateIso(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final direct = DateTime.tryParse(text);
    if (direct != null) {
      return _toDateIso(direct);
    }
    final slash = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$',
    ).firstMatch(text);
    if (slash != null) {
      final d = int.tryParse(slash.group(1)!);
      final m = int.tryParse(slash.group(2)!);
      var y = int.tryParse(slash.group(3)!);
      if (d == null || m == null || y == null) {
        return null;
      }
      if (y < 100) {
        y += 2000;
      }
      final dt = DateTime.tryParse(
        '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}',
      );
      if (dt != null) {
        return _toDateIso(dt);
      }
    }
    return null;
  }

  void _setScanMode(_OcrScanMode mode) {
    if (_isLoading || _ocrScanMode == mode) {
      return;
    }
    setState(() {
      _ocrScanMode = mode;
    });
  }

  bool _shouldBulkApplyTypeOnChatImport(_EditableDraftItem item) {
    if (item.needsReview) {
      return true;
    }
    return !_hasStrongTypeSignal(item);
  }

  bool _hasStrongTypeSignal(_EditableDraftItem item) {
    final hint = item.categoryHint.toLowerCase().trim();
    final desc = item.descriptionController.text.toLowerCase().trim();
    const strongOutHints = <String>[
      'bahan baku',
      'operasional',
      'gaji',
      'utang',
      'prive',
      'pengeluaran',
      'expense',
      'out',
    ];
    const strongInHints = <String>[
      'penjualan',
      'pemasukan',
      'income',
      'in',
      'produk',
      'kue',
      'snack',
      'minuman',
    ];
    for (final keyword in [...strongOutHints, ...strongInHints]) {
      if (hint.contains(keyword)) {
        return true;
      }
    }
    const strongOutDesc = <String>[
      'beli',
      'bayar',
      'gaji',
      'sewa',
      'listrik',
      'air',
      'bahan baku',
      'operasional',
      'pengeluaran',
      'out',
    ];
    const strongInDesc = <String>['jual', 'penjualan', 'pemasukan', 'in'];
    for (final keyword in [...strongOutDesc, ...strongInDesc]) {
      if (desc.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  bool _looksLikeProductLine(_EditableDraftItem item) {
    final hint = item.categoryHint.toLowerCase();
    if (hint.contains('makanan') ||
        hint.contains('kue') ||
        hint.contains('produk') ||
        hint.contains('penjualan') ||
        hint.contains('snack') ||
        hint.contains('minuman')) {
      return true;
    }

    final desc = item.descriptionController.text.toLowerCase().trim();
    if (desc.isEmpty || !RegExp(r'[a-z]').hasMatch(desc)) {
      return false;
    }

    const expenseKeywords = <String>[
      'beli',
      'bayar',
      'gaji',
      'sewa',
      'listrik',
      'air',
      'bbm',
      'bahan baku',
      'operasional',
      'utang',
      'prive',
    ];
    for (final keyword in expenseKeywords) {
      if (desc.contains(keyword)) {
        return false;
      }
    }
    return true;
  }

  int _parseAmountInput(String text) {
    final raw = text.toLowerCase().trim();
    if (raw.isEmpty) {
      return 0;
    }
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    final unitMatch = RegExp(
      r'^([0-9]+(?:[.,][0-9]+)?)(k|rb|ribu|jt|juta)$',
    ).firstMatch(compact);
    if (unitMatch != null) {
      final numberPart = unitMatch.group(1) ?? '';
      final unit = unitMatch.group(2) ?? '';
      final normalized = numberPart.replaceAll(',', '.');
      final value = double.tryParse(normalized);
      if (value == null) {
        return 0;
      }
      final multiplier = (unit == 'jt' || unit == 'juta') ? 1000000 : 1000;
      return (value * multiplier).round();
    }

    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return 0;
    }
    return int.tryParse(digitsOnly) ?? 0;
  }

  String _applyAuditTag(String description) {
    final clean = description.trim();
    if (_providerTrail.contains('chat-import')) {
      final suffix =
          _chatImportHash.isEmpty
              ? '[chat_import]'
              : '[chat_import:${_chatImportHash.substring(0, 8)}]';
      if (clean.toLowerCase().contains('[chat_import')) {
        return clean;
      }
      return '$clean $suffix'.trim();
    }
    final suffix =
        _ocrScanHash.isEmpty
            ? '[ocr_scan]'
            : '[ocr_scan:${_ocrScanHash.substring(0, 8)}]';
    if (clean.toLowerCase().contains('[ocr_scan')) {
      return clean;
    }
    return '$clean $suffix'.trim();
  }

  void _showUndoSaveSnackBar({
    required ScaffoldMessengerState messenger,
    required TransactionProvider transactionProvider,
    required AuthProvider auth,
    required List<TransactionModel> savedTransactions,
    required String message,
  }) {
    if (savedTransactions.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    var undone = false;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: 'Urungkan',
          onPressed: () async {
            if (undone) {
              return;
            }
            undone = true;
            var reverted = 0;
            final deletedBy = auth.currentUser?.username ?? 'system';
            for (final tx in savedTransactions) {
              if (tx.id == null) {
                continue;
              }
              try {
                await transactionProvider.deleteTransactionWithAudit(
                  transaction: tx,
                  reason: 'Urungkan simpan cepat OCR/Chat import',
                  deletedBy: deletedBy,
                );
                reverted += 1;
              } catch (_) {}
            }
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Urungkan selesai: $reverted transaksi dibatalkan.',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _buildOcrScanHash({
    required List<int> imageBytes,
    required String mimeType,
  }) {
    final bytesDigest = sha256.convert(imageBytes).toString();
    final payload = '$mimeType|$bytesDigest';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  DateTime _parseDateOrNow(String iso) {
    final parsed = DateTime.tryParse(iso.trim());
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _toDateIso(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  String _dateKey(String iso) {
    final parsed = DateTime.tryParse(iso.trim());
    if (parsed == null) {
      return '';
    }
    return _toDateIso(parsed);
  }

  String _dateLabel(String iso) {
    final parsed = DateTime.tryParse(iso.trim());
    if (parsed == null) {
      return 'Belum diset';
    }
    return DateFormat('dd MMM yyyy', 'id_ID').format(parsed);
  }

  String _typeLabel(String type) => type == 'OUT' ? 'KELUAR' : 'MASUK';

  Future<void> _pickDateForItem(int index) async {
    final item = _draftItems[index];
    final picked = await showDatePicker(
      context: context,
      initialDate: _parseDateOrNow(item.dateIso),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih tanggal transaksi',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      item.dateIso = _toDateIso(picked);
    });
  }

  Future<void> _pickAndApplyDateToBelow(int startIndex) async {
    final item = _draftItems[startIndex];
    final picked = await showDatePicker(
      context: context,
      initialDate: _parseDateOrNow(item.dateIso),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Terapkan tanggal ke item di bawah',
    );
    if (picked == null || !mounted) {
      return;
    }
    final dateIso = _toDateIso(picked);
    setState(() {
      for (int i = startIndex; i < _draftItems.length; i++) {
        _draftItems[i].dateIso = dateIso;
      }
    });
  }

  Widget _buildDateGroupHeader(int index) {
    final item = _draftItems[index];
    final label = _dateLabel(item.dateIso);
    final hasDate = item.dateIso.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6DEF8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, size: 16, color: Color(0xFF594596)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hasDate
                  ? 'Tanggal: $label'
                  : 'Tanggal belum diset (perlu review)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: hasDate ? Colors.black87 : const Color(0xFF8A6D1A),
              ),
            ),
          ),
          TextButton(
            onPressed:
                _isLoading ? null : () => _pickAndApplyDateToBelow(index),
            child: const Text('Tanggal Baru dari Sini'),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftItemCard(_EditableDraftItem item, int index) {
    final isExpanded =
        !_isCompactReviewMode || _expandedDraftIndexes.contains(index);
    final compactAmount = NumberFormat.decimalPattern(
      'id_ID',
    ).format(_parseAmountInput(item.amountController.text));
    final compactDescription = item.descriptionController.text.trim();
    final compactDate = _dateLabel(item.dateIso);

    return Card(
      color: item.needsReview ? const Color(0xFFFFF8E1) : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: item.selected,
                  onChanged: (value) {
                    setState(() {
                      item.selected = value ?? false;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    'Transaksi ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text('OCR ${item.confidence}%'),
                if (_isCompactReviewMode)
                  IconButton(
                    tooltip: isExpanded ? 'Tutup detail' : 'Buka detail',
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedDraftIndexes.remove(index);
                        } else {
                          _expandedDraftIndexes.add(index);
                        }
                      });
                    },
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                  ),
              ],
            ),
            if (item.needsReview) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.warning.isNotEmpty
                          ? item.warning
                          : 'AI ragu pada baris ini. Mohon cek dan edit manual.',
                      style: const TextStyle(
                        color: Color(0xFF8A6D1A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_isCompactReviewMode && !isExpanded) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_typeLabel(item.type)} • Rp $compactAmount • Tanggal: $compactDate',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      compactDescription.isEmpty ? '-' : compactDescription,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isExpanded) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('MASUK'),
                    selected: item.type == 'IN',
                    onSelected: (_) => setState(() => item.type = 'IN'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('KELUAR'),
                    selected: item.type == 'OUT',
                    onSelected: (_) => setState(() => item.type = 'OUT'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: item.amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nominal',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: item.descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Keterangan',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tanggal: ${_dateLabel(item.dateIso)}',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            item.dateIso.trim().isEmpty
                                ? const Color(0xFF8A6D1A)
                                : Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ubah tanggal item ini',
                    icon: const Icon(Icons.edit_calendar_outlined),
                    onPressed:
                        _isLoading ? null : () => _pickDateForItem(index),
                  ),
                  IconButton(
                    tooltip: 'Terapkan tanggal ini ke item di bawah',
                    icon: const Icon(Icons.south_outlined),
                    onPressed:
                        _isLoading
                            ? null
                            : () => _pickAndApplyDateToBelow(index),
                  ),
                ],
              ),
              if (item.dateSource != 'explicit') ...[
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sumber tanggal: ${item.dateSource == 'inferred' ? 'inferensi AI (cek ulang)' : 'tidak diketahui'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8A6D1A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kategori tebakan: ${item.categoryHint.isEmpty ? '-' : item.categoryHint}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Catatan (OCR Asistif)')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset + 24),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE8A1)),
            ),
            child: const Text(
              'Foto 1 halaman catatan. Hasil scan akan jadi daftar draft dan wajib Anda cek sebelum disimpan.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Mode Cepat'),
                selected: _ocrScanMode == _OcrScanMode.fast,
                onSelected: (_) => _setScanMode(_OcrScanMode.fast),
              ),
              ChoiceChip(
                label: const Text('Mode Akurat'),
                selected: _ocrScanMode == _OcrScanMode.accurate,
                onSelected: (_) => _setScanMode(_OcrScanMode.accurate),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _ocrScanMode == _OcrScanMode.fast
                ? 'Cepat: Gemini Lite lalu fallback Groq.'
                : 'Akurat: OCR diteruskan ke Chat untuk review terstruktur (human-in-the-loop).',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      _isLoading || _aiBlocked
                          ? null
                          : () => _pickAndProcess(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Ambil Foto'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _isLoading || _aiBlocked
                          ? null
                          : () => _pickAndProcess(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Pilih Galeri'),
                ),
              ),
            ],
          ),
          if (_imageBytes != null && _imageMimeType != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _isLoading || _aiBlocked
                        ? null
                        : _confirmAndRescanCurrentImage,
                icon: const Icon(Icons.refresh),
                label: const Text('Scan Ulang Foto Ini'),
              ),
            ),
          ],
          if (_aiBlocked) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFCDD2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFB71C1C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _aiBlockedMessage ??
                          'Fitur AI sedang tidak tersedia. Coba lagi nanti.',
                      style: const TextStyle(color: Color(0xFFB71C1C)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_providerAttemptLogs.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.alt_route,
                        size: 16,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Log Fallback OCR',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _isOcrLogExpanded = !_isOcrLogExpanded;
                          });
                        },
                        icon: Icon(
                          _isOcrLogExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                        ),
                        label: Text(
                          _isOcrLogExpanded ? 'Sembunyikan' : 'Tampilkan',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (_isOcrLogExpanded) ...[
                    const SizedBox(height: 6),
                    ..._providerAttemptLogs.map(
                      (log) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${_providerLabel(log.providerId)}'
                          '${log.stage == null || log.stage!.trim().isEmpty ? '' : ' [${_providerStageLabel(log.stage!)}]'}: '
                          '${_providerStatusLabel(log)} | '
                          'Reason: ${_providerDetailLabel(log)} | '
                          'Latency: ${log.elapsedMs > 0 ? '${log.elapsedMs} ms' : '-'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            ),
          if (_imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_imagePath!),
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!_isLoading &&
              _lastErrorMessage != null &&
              _imageBytes != null &&
              _imageMimeType != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCDD2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lastErrorMessage!,
                    style: const TextStyle(color: Color(0xFFB71C1C)),
                  ),
                  if (_lastRejectedReason != null) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Tip: pastikan foto memuat tulisan transaksi + nominal yang jelas.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _aiBlocked ? null : _processCurrentImage,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi'),
                    ),
                  ),
                ],
              ),
            ),
          if (_draftItems.isNotEmpty)
            Builder(
              builder: (context) {
                final selectedTotal = _selectedTotalAmount;
                final noteTotals = _detectedNoteTotals;
                final currency = NumberFormat.currency(
                  locale: 'id_ID',
                  symbol: 'Rp ',
                  decimalDigits: 0,
                );
                final selectedByDate = _selectedTotalsByDate();
                final persistedByDate = _persistedTotalsByDate(
                  context.read<TransactionProvider>(),
                );
                var groupCount = 0;
                for (int i = 0; i < _draftItems.length; i++) {
                  if (i == 0 ||
                      _dateKey(_draftItems[i].dateIso) !=
                          _dateKey(_draftItems[i - 1].dateIso)) {
                    groupCount += 1;
                  }
                }
                var segmentIndex = -1;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Review Hasil Scan (${_draftItems.length} transaksi)',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Terdeteksi ${_draftItems.length} transaksi, $_reviewCount perlu review.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      if (_hasInferenceReviewWarning) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFFE8A1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Data terinferensi/parsial terdeteksi. Wajib cek manual sebelum simpan.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8A6D1A),
                                ),
                              ),
                              if (_isPartialDayImport)
                                const Text(
                                  '- Catatan kemungkinan hanya potongan hari operasional.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              if (_missingOpeningBlock)
                                const Text(
                                  '- Blok pembuka hari tidak lengkap/tidak ditemukan.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              if (_missingClosingTotal)
                                const Text(
                                  '- Total penutup hari tidak ditemukan, data bisa belum lengkap.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ..._inferenceNotes
                                  .take(3)
                                  .map(
                                    (note) => Text(
                                      '- $note',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ],
                      if (_missingDateCount > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$_missingDateCount item belum punya tanggal. Mohon review sebelum simpan.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8A6D1A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (_detectedDate.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Tanggal terdeteksi: $_detectedDate',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                      if (_notesFound.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Catatan non-transaksi:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        ..._notesFound
                            .take(4)
                            .map(
                              (line) => Text(
                                '• $line',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                      ],
                      if (_ignoredLines.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_ignoredLines.length} baris diabaikan (bukan transaksi).',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _buildMassActionBar(),
                      const SizedBox(height: 8),
                      for (int i = 0; i < _draftItems.length; i++) ...[
                        if (i == 0 ||
                            _dateKey(_draftItems[i].dateIso) !=
                                _dateKey(_draftItems[i - 1].dateIso)) ...[
                          () {
                            segmentIndex += 1;
                            return _buildDateGroupHeader(i);
                          }(),
                        ],
                        _buildDraftItemCard(_draftItems[i], i),
                        if (i == _draftItems.length - 1 ||
                            _dateKey(_draftItems[i].dateIso) !=
                                _dateKey(_draftItems[i + 1].dateIso))
                          _buildDateGroupSummaryCard(
                            currency: currency,
                            dateIso: _draftItems[i].dateIso,
                            scanTotal:
                                selectedByDate[_dateKey(
                                  _draftItems[i].dateIso,
                                )] ??
                                0,
                            persistedTotal:
                                persistedByDate[_dateKey(
                                  _draftItems[i].dateIso,
                                )] ??
                                0,
                            noteTotal: _resolveNoteTotalForSegment(
                              groupCount: groupCount,
                              segmentIndex: segmentIndex,
                              noteTotals: noteTotals,
                            ),
                          ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total kalkulasi AI (dipilih): ${currency.format(selectedTotal)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Validasi per tanggal ditampilkan di bawah tiap grup.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _saveSelectedDrafts,
                          icon: const Icon(Icons.save_alt),
                          label: Text('Simpan $_selectedCount Transaksi'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _quotaTimer?.cancel();
    _clearDraftItems();
    super.dispose();
  }
}

class _ProviderAttemptLog {
  const _ProviderAttemptLog({
    required this.providerId,
    this.stage,
    required this.status,
    required this.detail,
    required this.startedAt,
    this.elapsedMs = 0,
  });

  final String providerId;
  final String? stage;
  final String status;
  final String? detail;
  final DateTime startedAt;
  final int elapsedMs;

  _ProviderAttemptLog copyWith({
    String? providerId,
    String? stage,
    String? status,
    String? detail,
    DateTime? startedAt,
    int? elapsedMs,
  }) {
    return _ProviderAttemptLog(
      providerId: providerId ?? this.providerId,
      stage: stage ?? this.stage,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      startedAt: startedAt ?? this.startedAt,
      elapsedMs: elapsedMs ?? this.elapsedMs,
    );
  }
}

class _TypeSignal {
  const _TypeSignal({
    required this.predictedType,
    required this.strongOut,
    required this.strongIn,
  });

  final String predictedType;
  final bool strongOut;
  final bool strongIn;
}

class _EditableDraftItem {
  _EditableDraftItem({
    required this.selected,
    required this.type,
    required int amount,
    required String description,
    required this.originalDescription,
    required this.categoryHint,
    required this.dateIso,
    required this.dateSource,
    required this.confidence,
    required this.rawText,
    required this.needsReview,
    required this.warning,
  }) : amountController = TextEditingController(text: '$amount'),
       descriptionController = TextEditingController(text: description);

  bool selected;
  String type;
  final TextEditingController amountController;
  final TextEditingController descriptionController;
  final String originalDescription;
  final String categoryHint;
  String dateIso;
  final String dateSource;
  final int confidence;
  final String rawText;
  final bool needsReview;
  final String warning;

  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
  }
}
