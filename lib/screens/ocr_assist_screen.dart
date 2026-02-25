import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_import_draft.dart';
import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../services/chat_import_audit_service.dart';
import '../services/ocr_import_audit_service.dart';
import '../services/ai_insight_service.dart';
import '../services/ai_ocr_service.dart';
import '../services/ocr_learning_dictionary_service.dart';
import '../services/ai_quota_guard_service.dart';
import '../providers/transaction_provider.dart';

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

  int get _selectedCount => _draftItems.where((item) => item.selected).length;
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

  void _recordProviderEvent(String providerId, String status, String? detail) {
    final now = DateTime.now();
    if (status == 'try') {
      _providerAttemptLogs.add(
        _ProviderAttemptLog(
          providerId: providerId,
          status: status,
          detail: detail,
          startedAt: now,
        ),
      );
      return;
    }
    for (var i = _providerAttemptLogs.length - 1; i >= 0; i--) {
      final log = _providerAttemptLogs[i];
      if (log.providerId == providerId && log.status == 'try') {
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
        onProviderEvent: (providerId, status, detail) {
          if (!mounted) {
            return;
          }
          setState(() {
            if (status == 'try' && !_providerTrail.contains(providerId)) {
              _providerTrail.add(providerId);
            }
            _recordProviderEvent(providerId, status, detail);
          });
        },
      );
      await OcrLearningDictionaryService.preloadFromProductsIfNeeded();
      final dictionary = await OcrLearningDictionaryService.getDictionary();
      final editableItems =
          batch.transactions.map((item) {
            final correctedDescription =
                OcrLearningDictionaryService.applyCorrection(
                  item.description,
                  dictionary,
                );
            return _EditableDraftItem(
              selected: true,
              type: item.type,
              amount: item.amount,
              description: correctedDescription,
              originalDescription: item.description,
              categoryHint: item.categoryHint,
              dateIso: item.dateIso,
              dateSource: item.dateSource,
              confidence: item.confidence,
              rawText: item.rawText,
              needsReview: item.needsReview,
              warning: item.warning,
            );
          }).toList();
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
      _clearDraftItems();
      _detectedDate = '';
      _notesFound.clear();
      _ignoredLines.clear();
      if (mounted) {
        Navigator.of(context).pop();
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

  void _clearDraftItems() {
    for (final item in _draftItems) {
      item.dispose();
    }
    _draftItems.clear();
  }

  void _applyMajorityTypeDefault() {
    if (_draftItems.isEmpty) {
      return;
    }
    var inCount = 0;
    var outCount = 0;
    var productLikeCount = 0;
    for (final item in _draftItems) {
      if (item.type == 'OUT') {
        outCount += 1;
      } else {
        inCount += 1;
      }
      if (_looksLikeProductLine(item)) {
        productLikeCount += 1;
      }
    }
    String? majorityType;
    if (inCount == outCount) {
      final threshold = (_draftItems.length / 2).ceil();
      if (productLikeCount >= threshold) {
        majorityType = 'IN';
      }
    } else {
      majorityType = inCount > outCount ? 'IN' : 'OUT';
    }
    if (majorityType == null) {
      return;
    }
    final isChatImport = _providerTrail.contains('chat-import');
    for (final item in _draftItems) {
      if (isChatImport && !_shouldBulkApplyTypeOnChatImport(item)) {
        continue;
      }
      item.type = majorityType;
    }
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
    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
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
            const SizedBox(height: 6),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('IN'),
                  selected: item.type == 'IN',
                  onSelected: (_) => setState(() => item.type = 'IN'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('OUT'),
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
                  onPressed: _isLoading ? null : () => _pickDateForItem(index),
                ),
                IconButton(
                  tooltip: 'Terapkan tanggal ini ke item di bawah',
                  icon: const Icon(Icons.south_outlined),
                  onPressed:
                      _isLoading ? null : () => _pickAndApplyDateToBelow(index),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Catatan (OCR Asistif)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                  const Row(
                    children: [
                      Icon(Icons.alt_route, size: 16, color: Colors.black54),
                      SizedBox(width: 6),
                      Text(
                        'Log Fallback OCR',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ..._providerAttemptLogs.map(
                    (log) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_providerLabel(log.providerId)}: '
                        '${_providerStatusLabel(log)} | '
                        'Reason: ${_providerDetailLabel(log)} | '
                        'Latency: ${log.elapsedMs > 0 ? '${log.elapsedMs} ms' : '-'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
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
                      Wrap(
                        spacing: 4,
                        runSpacing: 0,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed:
                                _isLoading ? null : () => _selectAll(true),
                            child: const Text('Pilih Semua'),
                          ),
                          TextButton(
                            onPressed:
                                _isLoading ? null : () => _selectAll(false),
                            child: const Text('Batal Pilihan'),
                          ),
                          TextButton(
                            onPressed:
                                _isLoading ? null : () => _setAllType('IN'),
                            child: const Text('Set IN'),
                          ),
                          TextButton(
                            onPressed:
                                _isLoading ? null : () => _setAllType('OUT'),
                            child: const Text('Set OUT'),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('Dipilih: $_selectedCount'),
                          ),
                        ],
                      ),
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
    required this.status,
    required this.detail,
    required this.startedAt,
    this.elapsedMs = 0,
  });

  final String providerId;
  final String status;
  final String? detail;
  final DateTime startedAt;
  final int elapsedMs;

  _ProviderAttemptLog copyWith({
    String? providerId,
    String? status,
    String? detail,
    DateTime? startedAt,
    int? elapsedMs,
  }) {
    return _ProviderAttemptLog(
      providerId: providerId ?? this.providerId,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      startedAt: startedAt ?? this.startedAt,
      elapsedMs: elapsedMs ?? this.elapsedMs,
    );
  }
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
