import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/product_provider.dart';
import '../providers/production_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/user_provider.dart';
import '../services/backup_service.dart';
import '../services/cloud_drive_service.dart';
import '../widgets/account_panel.dart';
import 'login_screen.dart';
import 'manage_users_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _autoBackupEnabled = true;
  bool _isTestingCloud = false;
  bool _isRestoringCloud = false;

  @override
  void initState() {
    super.initState();
    _loadAutoBackupSetting();
  }

  Future<void> _loadAutoBackupSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _autoBackupEnabled =
          prefs.getBool(BackupService.autoBackupEnabledKey) ?? true;
    });
  }

  Future<void> _setAutoBackupEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(BackupService.autoBackupEnabledKey, value);
    if (!mounted) {
      return;
    }
    setState(() {
      _autoBackupEnabled = value;
    });
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    final backgroundColor =
        isError ? const Color(0xFF8D1B3D) : const Color(0xFFA5D6A7);
    final textColor = isError ? Colors.white : Colors.black87;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: textColor)),
        backgroundColor: backgroundColor,
      ),
    );
  }

  Future<void> _backupDatabase() async {
    if (_isBackingUp) {
      return;
    }
    setState(() {
      _isBackingUp = true;
    });

    try {
      final result = await BackupService.backupDatabase(shareAfter: true);
      if (!mounted) {
        return;
      }
      final downloadMessage =
          result.downloadPath != null
              ? 'Backup tersimpan di: ${result.downloadPath}'
              : 'Backup selesai, tetapi gagal simpan ke folder Download.';
      _showSnackBar(context, downloadMessage, isError: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(context, 'Gagal membuat backup: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
        });
      }
    }
  }

  Future<void> _restoreDatabase() async {
    if (_isRestoring) {
      return;
    }
    final choice = await _showRestoreOptions();
    if (choice == null) {
      return;
    }
    if (choice == _RestoreChoice.manual) {
      await _restoreManual();
    } else {
      await _restoreAutoBackup();
    }
  }

  Future<_RestoreChoice?> _showRestoreOptions() {
    return showModalBottomSheet<_RestoreChoice>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Pilih Sumber Restore',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Pilih File Manual'),
                subtitle: const Text('Ambil dari Download/Drive/WhatsApp'),
                onTap: () => Navigator.of(context).pop(_RestoreChoice.manual),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Gunakan Auto-backup'),
                subtitle: const Text('Daftar backup otomatis aplikasi'),
                onTap: () => Navigator.of(context).pop(_RestoreChoice.auto),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Konfirmasi Restore'),
          content: const Text(
            'Peringatan: Data saat ini akan dihapus dan diganti dengan data backup. Lanjutkan?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ya, Restore'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _restoreManual() async {
    final confirmed = await _confirmRestore();
    if (!confirmed) {
      return;
    }
    await _performRestore(() => BackupService.restoreDatabase());
  }

  Future<void> _restoreAutoBackup() async {
    final files = await BackupService.getAutoBackupFiles();
    if (!mounted) {
      return;
    }
    if (files.isEmpty) {
      _showSnackBar(
        context,
        'Belum ada auto-backup yang tersedia.',
        isError: true,
      );
      return;
    }
    final selected = await showModalBottomSheet<_AutoBackupChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final modified = file.lastModifiedSync();
              final label = DateFormat(
                'd MMM y HH:mm',
                'id_ID',
              ).format(modified);
              return ListTile(
                leading: const Icon(Icons.restore),
                title: Text('Backup $label'),
                subtitle: Text(p.basename(file.path)),
                onTap:
                    () => Navigator.of(
                      context,
                    ).pop(_AutoBackupChoice(filePath: file.path)),
              );
            },
          ),
        );
      },
    );
    if (selected == null) {
      return;
    }
    final confirmed = await _confirmRestore();
    if (!confirmed) {
      return;
    }
    await _performRestore(
      () => BackupService.restoreDatabaseFromPath(selected.filePath),
    );
  }

  Future<void> _performRestore(Future<RestoreResult?> Function() action) async {
    if (_isRestoring) {
      return;
    }
    setState(() {
      _isRestoring = true;
    });
    try {
      final restored = await action();
      if (!mounted) {
        return;
      }
      if (restored == null) {
        return;
      }

      await _reloadDataAfterRestore();

      if (!mounted) {
        return;
      }
      _showSnackBar(
        context,
        'Data berhasil dipulihkan. Jika data belum berubah, silakan buka kembali aplikasi.',
        isError: false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is RestoreFailure && error.rolledBack) {
        _showSnackBar(context, error.message, isError: true);
      } else {
        _showSnackBar(context, 'Gagal restore: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  Future<void> _reloadDataAfterRestore() async {
    await context.read<TransactionProvider>().loadTransactions();
    await context.read<TransactionProvider>().loadDeletedTransactions();
    await context.read<ProductProvider>().loadProducts();
    await context.read<CategoryProvider>().loadCategories();
    await context.read<ProductionProvider>().loadTodayProduction();
    context.read<TransactionProvider>().markRestored();
  }

  Future<void> _simulateBackupReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp =
        DateTime.now().subtract(const Duration(days: 4)).millisecondsSinceEpoch;
    await prefs.setInt(BackupService.lastBackupKey, timestamp);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Timestamp backup berhasil dimundurkan 4 hari.'),
      ),
    );
  }

  Future<void> _uploadCloudBackup() async {
    if (_isTestingCloud) {
      return;
    }
    setState(() {
      _isTestingCloud = true;
    });
    try {
      final success = await CloudDriveService().uploadDatabaseBackup();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context,
        success ? 'Backup ke Google Drive berhasil.' : 'Login dibatalkan.',
        isError: !success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context,
        'Gagal backup ke Google Drive: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTestingCloud = false;
        });
      }
    }
  }

  Future<void> _restoreFromCloud() async {
    if (_isRestoringCloud) {
      return;
    }
    final confirmed = await _confirmRestore();
    if (!confirmed) {
      return;
    }
    setState(() {
      _isRestoringCloud = true;
    });
    try {
      final result = await CloudDriveService().restoreLatestDatabaseBackup();
      if (!mounted) {
        return;
      }
      if (result == null) {
        _showSnackBar(context, 'Login dibatalkan.', isError: true);
        return;
      }
      await _reloadDataAfterRestore();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context,
        'Restore cloud berhasil (${result.fileName}).',
        isError: false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(context, 'Gagal restore dari cloud: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isRestoringCloud = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final isOwner = user?.role == 'owner';

    return AccountPanel(
      onLogout: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Konfirmasi Keluar'),
              content: const Text('Apakah Anda yakin ingin keluar?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Batal'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Ya, Keluar'),
                ),
              ],
            );
          },
        );

        if (confirmed != true) {
          return;
        }

        context.read<TransactionProvider>().clearTransactions();
        authProvider.logout();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      },
      onManageUsers:
          isOwner
              ? () async {
                await context.read<UserProvider>().loadUsers();
                if (!context.mounted) {
                  return;
                }
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ManageUsersScreen()),
                );
              }
              : null,
      onBackup: isOwner ? _backupDatabase : null,
      isBackingUp: _isBackingUp,
      onRestore: isOwner ? _restoreDatabase : null,
      isRestoring: _isRestoring,
      onDebugSimulateBackup: isOwner ? _simulateBackupReminder : null,
      autoBackupEnabled: _autoBackupEnabled,
      onToggleAutoBackup: isOwner ? _setAutoBackupEnabled : null,
      onTestCloudConnection: isOwner ? _uploadCloudBackup : null,
      onRestoreCloudBackup: isOwner ? _restoreFromCloud : null,
      isTestingCloud: _isTestingCloud,
      isRestoringCloud: _isRestoringCloud,
    );
  }
}

enum _RestoreChoice { manual, auto }

class _AutoBackupChoice {
  const _AutoBackupChoice({required this.filePath});

  final String filePath;
}
