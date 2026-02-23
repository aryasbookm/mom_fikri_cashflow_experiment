import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/ocr_transaction_draft.dart';
import '../services/ai_insight_service.dart';
import '../services/ai_ocr_service.dart';
import 'add_transaction_screen.dart';

class OcrAssistScreen extends StatefulWidget {
  const OcrAssistScreen({super.key});

  @override
  State<OcrAssistScreen> createState() => _OcrAssistScreenState();
}

class _OcrAssistScreenState extends State<OcrAssistScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = false;
  String? _imagePath;
  OcrTransactionDraft? _draft;

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
      _draft = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final mimeType = _detectMimeType(file.path);
      final draft = await AiOcrService().extractDraftFromImageBytes(
        imageBytes: bytes,
        mimeType: mimeType,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _draft = draft;
      });
    } on AiRateLimitException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'AI sedang sibuk. Coba lagi dalam ${error.retryAfterSeconds} detik.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memproses scan: $error')));
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

  Future<void> _useDraft() async {
    final draft = _draft;
    if (draft == null) {
      return;
    }

    DateTime? parsedDate;
    if (draft.dateIso.isNotEmpty) {
      parsedDate = DateTime.tryParse(draft.dateIso);
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => AddTransactionScreen(
              initialType: draft.type,
              lockTypeSelection: false,
              initialAmount: draft.amount > 0 ? '${draft.amount}' : null,
              initialDescription:
                  draft.description.isNotEmpty ? draft.description : null,
              initialCategoryHint:
                  draft.categoryHint.isNotEmpty ? draft.categoryHint : null,
              initialDate: parsedDate,
              initialManualIncomeInput: draft.type == 'IN',
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final datePreview =
        draft != null && draft.dateIso.isNotEmpty
            ? DateFormat(
              'dd MMM yyyy',
              'id_ID',
            ).format(DateTime.tryParse(draft.dateIso) ?? DateTime.now())
            : '-';

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
              'Foto 1 transaksi dulu. Hasil scan akan jadi draft dan wajib Anda cek sebelum disimpan.',
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
          if (draft != null)
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
                  const Text(
                    'Konfirmasi Hasil Scan',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Jenis: ${draft.type == 'IN' ? 'Pemasukan' : 'Pengeluaran'}',
                  ),
                  Text(
                    'Nominal: Rp ${NumberFormat('#,##0', 'id_ID').format(draft.amount)}',
                  ),
                  Text('Tanggal: $datePreview'),
                  Text(
                    'Kategori tebakan: ${draft.categoryHint.isEmpty ? '-' : draft.categoryHint}',
                  ),
                  Text(
                    'Keterangan: ${draft.description.isEmpty ? '-' : draft.description}',
                  ),
                  Text('Kepercayaan OCR: ${draft.confidence}%'),
                  const SizedBox(height: 8),
                  const Text(
                    'Teks terbaca:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    draft.rawText.isEmpty ? '-' : draft.rawText,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _useDraft,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Gunakan Draft ke Form Transaksi'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
