import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/backup_service.dart';
import 'main_screen.dart';

class FirstInstallOnboardingScreen extends StatefulWidget {
  const FirstInstallOnboardingScreen({super.key});

  @override
  State<FirstInstallOnboardingScreen> createState() =>
      _FirstInstallOnboardingScreenState();
}

class _FirstInstallOnboardingScreenState
    extends State<FirstInstallOnboardingScreen> {
  final _accountFormKey = GlobalKey<FormState>();
  final _setupFormKey = GlobalKey<FormState>();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final TextEditingController _openingBalanceController =
      TextEditingController();

  DateTime _cutoffDate = DateTime.now();
  int _stepIndex = 0;
  bool _isSaving = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  Future<void> _pickCutoffDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _cutoffDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() {
        _cutoffDate = DateTime(picked.year, picked.month, picked.day, 8);
      });
    }
  }

  void _nextStep() {
    if (_stepIndex == 0) {
      if (!(_accountFormKey.currentState?.validate() ?? false)) {
        return;
      }
    }
    setState(() {
      _stepIndex = 1;
    });
  }

  Future<void> _finishSetup() async {
    if (!(_accountFormKey.currentState?.validate() ?? false)) {
      setState(() {
        _stepIndex = 0;
      });
      return;
    }
    if (!(_setupFormKey.currentState?.validate() ?? false)) {
      return;
    }

    final openingBalance =
        int.tryParse(_openingBalanceController.text.trim()) ?? -1;
    if (openingBalance < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saldo awal wajib angka 0 atau lebih.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final authProvider = context.read<AuthProvider>();
    final categoryProvider = context.read<CategoryProvider>();
    final transactionProvider = context.read<TransactionProvider>();

    try {
      await DatabaseHelper.instance.setupFirstInstall(
        username: _usernameController.text.trim(),
        pin: _pinController.text.trim(),
        cutoffDate: _cutoffDate,
        openingBalance: openingBalance,
      );

      if (!mounted) {
        return;
      }

      final loggedIn = await authProvider.login(
        _usernameController.text.trim(),
        _pinController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      if (!loggedIn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setup selesai, tetapi login otomatis gagal.'),
          ),
        );
        return;
      }

      await categoryProvider.loadCategories();
      await transactionProvider.loadTransactions();
      // Set baseline reminder timestamp agar user baru tidak langsung "diserang"
      // warning backup di detik pertama onboarding selesai.
      await BackupService.markBackupSuccess();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        BackupService.onboardingCompletedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Setup gagal: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF8D1B3D);

    return Scaffold(
      appBar: AppBar(title: const Text('Setup Pertama Aplikasi')),
      body: SafeArea(
        child: Stepper(
          currentStep: _stepIndex,
          controlsBuilder: (context, details) {
            final isLast = _stepIndex == 1;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed:
                        _isSaving ? null : (isLast ? _finishSetup : _nextStep),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white70,
                    ),
                    child:
                        _isSaving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : Text(isLast ? 'Selesaikan Setup' : 'Lanjut'),
                  ),
                  if (_stepIndex > 0)
                    TextButton(
                      onPressed:
                          _isSaving
                              ? null
                              : () {
                                setState(() {
                                  _stepIndex = 0;
                                });
                              },
                      child: const Text('Kembali'),
                    ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Akun Owner'),
              isActive: _stepIndex >= 0,
              state: _stepIndex > 0 ? StepState.complete : StepState.indexed,
              content: Form(
                key: _accountFormKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username Owner',
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'Username wajib diisi.';
                        }
                        if (text.length < 3) {
                          return 'Minimal 3 karakter.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pinController,
                      decoration: const InputDecoration(labelText: 'PIN Owner'),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'PIN wajib diisi.';
                        }
                        if (text.length < 4) {
                          return 'PIN minimal 4 digit.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPinController,
                      decoration: const InputDecoration(
                        labelText: 'Konfirmasi PIN',
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      validator: (value) {
                        if ((value ?? '').trim() !=
                            _pinController.text.trim()) {
                          return 'Konfirmasi PIN tidak cocok.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            Step(
              title: const Text('Saldo Awal'),
              isActive: _stepIndex >= 1,
              content: Form(
                key: _setupFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tentukan tanggal mulai pencatatan dan saldo kas fisik saat tanggal tersebut.',
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _isSaving ? null : _pickCutoffDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tanggal Mulai (Cut-off)',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat(
                                'dd MMM yyyy',
                                'id_ID',
                              ).format(_cutoffDate),
                            ),
                            const Icon(Icons.calendar_today_outlined),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _openingBalanceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Saldo Awal Kas Fisik (Rp)',
                      ),
                      validator: (value) {
                        final parsed = int.tryParse((value ?? '').trim());
                        if (parsed == null) {
                          return 'Masukkan angka saldo awal.';
                        }
                        if (parsed < 0) {
                          return 'Saldo awal tidak boleh negatif.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Catatan: saldo awal akan dicatat sebagai transaksi pemasukan kategori "Saldo Awal".',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
