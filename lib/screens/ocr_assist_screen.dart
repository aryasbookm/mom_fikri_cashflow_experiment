import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../services/ai_insight_service.dart';
import '../services/ai_ocr_service.dart';
import '../services/ai_quota_guard_service.dart';
import '../providers/transaction_provider.dart';

class OcrAssistScreen extends StatefulWidget {
  const OcrAssistScreen({super.key});

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
  String _detectedDate = '';
  final List<String> _notesFound = [];
  final List<String> _ignoredLines = [];
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

  String get _providerTrailText {
    if (_providerTrail.isEmpty) {
      return '';
    }
    final ordered = <String>[];
    for (final id in _providerTrail) {
      if (!ordered.contains(id)) {
        ordered.add(id);
      }
    }
    return ordered
        .map((id) {
          switch (id) {
            case 'gemini':
              return 'Gemini';
            case 'groq':
              return 'Groq';
            default:
              return id;
          }
        })
        .join(' -> ');
  }

  @override
  void initState() {
    super.initState();
    _refreshAiQuotaState();
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
      _detectedDate = '';
      _notesFound.clear();
      _ignoredLines.clear();
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
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _clearDraftItems();
        _draftItems.addAll(
          batch.transactions.map(
            (item) => _EditableDraftItem(
              selected: true,
              type: item.type,
              amount: item.amount,
              description: item.description,
              categoryHint: item.categoryHint,
              dateIso: item.dateIso,
              confidence: item.confidence,
              rawText: item.rawText,
              needsReview: item.needsReview,
              warning: item.warning,
            ),
          ),
        );
        _detectedDate = batch.detectedDate;
        _notesFound
          ..clear()
          ..addAll(batch.notesFound);
        _ignoredLines
          ..clear()
          ..addAll(batch.ignoredLines);
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
    for (final item in selected) {
      final amount = int.tryParse(item.amountController.text.trim()) ?? 0;
      final description = item.descriptionController.text.trim();
      if (amount <= 0 || description.length < 3) {
        failed += 1;
        continue;
      }

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
      final txDate = DateTime(
        parsedDate?.year ?? now.year,
        parsedDate?.month ?? now.month,
        parsedDate?.day ?? now.day,
        now.hour,
        now.minute,
        now.second,
      );

      try {
        await transactionProvider.addTransaction(
          TransactionModel(
            type: item.type,
            amount: amount,
            categoryId: categoryId,
            description: description,
            date: txDate.toIso8601String(),
            userId: userId,
          ),
        );
        success += 1;
      } catch (_) {
        failed += 1;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });

    if (success > 0 && failed == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berhasil menyimpan $success transaksi.')),
      );
      _clearDraftItems();
      _detectedDate = '';
      _notesFound.clear();
      _ignoredLines.clear();
      Navigator.of(context).pop();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Selesai: berhasil $success, gagal $failed. Periksa data yang belum valid.',
        ),
      ),
    );
  }

  void _selectAll(bool selected) {
    setState(() {
      for (final item in _draftItems) {
        item.selected = selected;
      }
    });
  }

  void _clearDraftItems() {
    for (final item in _draftItems) {
      item.dispose();
    }
    _draftItems.clear();
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
              hasDate ? 'Tanggal: $label' : 'Tanggal belum diset (perlu review)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: hasDate ? Colors.black87 : const Color(0xFF8A6D1A),
              ),
            ),
          ),
          TextButton(
            onPressed: _isLoading ? null : () => _pickAndApplyDateToBelow(index),
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
                      _isLoading
                          ? null
                          : () => _pickAndApplyDateToBelow(index),
                ),
              ],
            ),
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
          if (_providerTrail.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alt_route, size: 16, color: Colors.black54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Provider dicoba: $_providerTrailText',
                      style: const TextStyle(fontSize: 12),
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
            Container(
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
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
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
                  Row(
                    children: [
                      TextButton(
                        onPressed: _isLoading ? null : () => _selectAll(true),
                        child: const Text('Pilih Semua'),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : () => _selectAll(false),
                        child: const Text('Batal Pilihan'),
                      ),
                      const Spacer(),
                      Text('Dipilih: $_selectedCount'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _draftItems.length; i++) ...[
                    if (i == 0 ||
                        _dateKey(_draftItems[i].dateIso) !=
                            _dateKey(_draftItems[i - 1].dateIso))
                      _buildDateGroupHeader(i),
                    _buildDraftItemCard(_draftItems[i], i),
                  ],
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

class _EditableDraftItem {
  _EditableDraftItem({
    required this.selected,
    required this.type,
    required int amount,
    required String description,
    required this.categoryHint,
    required this.dateIso,
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
  final String categoryHint;
  String dateIso;
  final int confidence;
  final String rawText;
  final bool needsReview;
  final String warning;

  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
  }
}
