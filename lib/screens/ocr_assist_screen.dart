import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../services/ai_insight_service.dart';
import '../services/ai_ocr_service.dart';
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
  String? _lastErrorMessage;
  String? _lastRejectedReason;

  int get _selectedCount => _draftItems.where((item) => item.selected).length;

  Future<void> _pickAndProcess(ImageSource source) async {
    if (_isLoading) {
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
      _lastErrorMessage = null;
      _lastRejectedReason = null;
    });

    try {
      final bytes = await file.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imageMimeType = _detectMimeType(file.path);
      });
      await _processCurrentImage();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _lastErrorMessage = 'Gagal membaca file gambar: $error';
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
    });

    try {
      final batch = await AiOcrService().extractDraftFromImageBytes(
        imageBytes: bytes,
        mimeType: mimeType,
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
            ),
          ),
        );
        _lastErrorMessage = null;
        _lastRejectedReason = null;
      });
    } on AiRateLimitException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastErrorMessage =
            'AI sedang sibuk. Coba lagi dalam ${error.retryAfterSeconds} detik.';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_lastErrorMessage!)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastErrorMessage = 'Gagal memproses scan: $error';
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

  String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
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

  Widget _buildDraftItemCard(_EditableDraftItem item, int index) {
    return Card(
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
                      _isLoading
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
                      _isLoading
                          ? null
                          : () => _pickAndProcess(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Pilih Galeri'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                      onPressed: _processCurrentImage,
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
                  for (int i = 0; i < _draftItems.length; i++)
                    _buildDraftItemCard(_draftItems[i], i),
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
  }) : amountController = TextEditingController(text: '$amount'),
       descriptionController = TextEditingController(text: description);

  bool selected;
  String type;
  final TextEditingController amountController;
  final TextEditingController descriptionController;
  final String categoryHint;
  final String dateIso;
  final int confidence;
  final String rawText;

  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
  }
}
