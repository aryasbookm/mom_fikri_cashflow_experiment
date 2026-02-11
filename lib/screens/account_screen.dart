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
  bool _isCloudAccountActionInProgress = false;
  bool _isCloudAccountConnected = false;
  String? _lastCloudBackupTimeIso;

  @override
  void initState() {
    super.initState();
    _loadAutoBackupSetting();
    _loadLastCloudBackupTime();
    _refreshCloudAccountStatus();
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

  Future<void> _loadLastCloudBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _lastCloudBackupTimeIso = prefs.getString(
        CloudDriveService.lastCloudBackupTimeKey,
      );
    });
  }

  Future<void> _refreshCloudAccountStatus() async {
    final connected = await CloudDriveService().isSignedIn();
    if (!mounted) {
      return;
    }
    setState(() {
      _isCloudAccountConnected = connected;
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
      if (success) {
        await _loadLastCloudBackupTime();
        await _refreshCloudAccountStatus();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context,
        CloudDriveService.userFriendlyMessage(
          error,
          fallback: 'Gagal backup ke Google Drive.',
        ),
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
    final selected = await _showCloudRestorePicker();
    if (selected == null) {
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
      final result = await CloudDriveService().restoreLatestDatabaseBackup(
        fileId: selected.fileId,
      );
      if (!mounted) {
        return;
      }
      if (result == null) {
        _showSnackBar(context, 'Login dibatalkan.', isError: true);
        return;
      }
      await _refreshCloudAccountStatus();
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
      _showSnackBar(
        context,
        CloudDriveService.userFriendlyMessage(
          error,
          fallback: 'Gagal restore dari cloud.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRestoringCloud = false;
        });
      }
    }
  }

  Future<void> _handleCloudAccountAction() async {
    if (_isCloudAccountActionInProgress) {
      return;
    }
    final service = CloudDriveService();
    final isConnected = await service.isSignedIn();
    if (!mounted) {
      return;
    }
    if (isConnected) {
      final confirmDisconnect = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Ganti Akun Google Drive'),
            content: const Text(
              'Akun saat ini akan diputus. Lanjutkan untuk memilih akun lain?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Lanjut'),
              ),
            ],
          );
        },
      );
      if (confirmDisconnect != true) {
        return;
      }
    }

    setState(() {
      _isCloudAccountActionInProgress = true;
    });
    try {
      if (isConnected) {
        await service.disconnectAccount();
        if (!mounted) {
          return;
        }
        _showSnackBar(
          context,
          'Akun Google Drive diputus. Silakan pilih akun untuk login ulang.',
          isError: false,
        );
        final relogin = await service.connectAccount();
        if (!mounted) {
          return;
        }
        _showSnackBar(
          context,
          relogin
              ? 'Akun Google Drive berhasil diganti.'
              : 'Pemilihan akun dibatalkan.',
          isError: !relogin,
        );
      } else {
        final connected = await service.connectAccount();
        if (!mounted) {
          return;
        }
        _showSnackBar(
          context,
          connected
              ? 'Akun Google Drive berhasil dihubungkan.'
              : 'Login dibatalkan.',
          isError: !connected,
        );
      }
      if (!mounted) {
        return;
      }
      await _loadLastCloudBackupTime();
      await _refreshCloudAccountStatus();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        context,
        CloudDriveService.userFriendlyMessage(
          error,
          fallback: 'Gagal memutus akun Google Drive.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCloudAccountActionInProgress = false;
        });
      }
    }
  }

  Future<_CloudBackupChoice?> _showCloudRestorePicker() async {
    late Future<List<Map<String, dynamic>>> backupsFuture;
    backupsFuture = CloudDriveService().getCloudBackupList();
    return showModalBottomSheet<_CloudBackupChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: backupsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Gagal mengambil daftar backup cloud.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            CloudDriveService.userFriendlyMessage(
                              snapshot.error ?? Exception('Unknown'),
                              fallback:
                                  'Terjadi kendala saat mengambil daftar backup cloud.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              setModalState(() {
                                backupsFuture =
                                    CloudDriveService().getCloudBackupList();
                              });
                            },
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    );
                  }

                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Tidak ada backup cloud ditemukan.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ListTile(
                        title: Text(
                          'Pilih Backup Cloud',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final id = item['id'] as String;
                            final rawName = item['name'] as String;
                            final displayName = rawName.replaceAll(
                              'Backup_MomFiqry_',
                              '',
                            );
                            final modifiedTime =
                                item['modifiedTime'] as String?;
                            final size = item['size'];
                            final subtitle =
                                '${_formatCloudDate(modifiedTime)} • ${_formatCloudSize(size)}';
                            return ListTile(
                              leading: const Icon(
                                Icons.cloud_download_outlined,
                              ),
                              title: Row(
                                children: [
                                  Expanded(child: Text(displayName)),
                                  if (index == 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: const Text(
                                        'Terbaru',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(subtitle),
                              trailing: const Icon(Icons.chevron_right),
                              onTap:
                                  () => Navigator.of(context).pop(
                                    _CloudBackupChoice(
                                      fileId: id,
                                      fileName: rawName,
                                    ),
                                  ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  String _formatCloudDate(String? iso) {
    if (iso == null || iso.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return '-';
    }
    return DateFormat('d MMM yyyy HH:mm', 'id_ID').format(parsed.toLocal());
  }

  String _formatCloudSize(dynamic rawSize) {
    final bytes = int.tryParse('$rawSize');
    if (bytes == null || bytes <= 0) {
      return 'Ukuran -';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _cloudBackupInfoText() {
    if (_lastCloudBackupTimeIso == null || _lastCloudBackupTimeIso!.isEmpty) {
      return 'Terakhir Backup Cloud: Belum ada backup';
    }
    final formatted = _formatCloudDate(_lastCloudBackupTimeIso);
    return 'Terakhir Backup Cloud: $formatted';
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
      onCloudAccountAction: isOwner ? _handleCloudAccountAction : null,
      isTestingCloud: _isTestingCloud,
      isRestoringCloud: _isRestoringCloud,
      isCloudAccountActionInProgress: _isCloudAccountActionInProgress,
      isCloudAccountConnected: _isCloudAccountConnected,
      cloudBackupInfoText: isOwner ? _cloudBackupInfoText() : null,
    );
  }
}

enum _RestoreChoice { manual, auto }

class _AutoBackupChoice {
  const _AutoBackupChoice({required this.filePath});

  final String filePath;
}

class _CloudBackupChoice {
  const _CloudBackupChoice({required this.fileId, required this.fileName});

  final String fileId;
  final String fileName;
}
