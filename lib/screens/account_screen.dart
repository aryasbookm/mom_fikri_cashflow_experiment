import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/product_provider.dart';
import '../providers/production_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/user_provider.dart';
import '../services/backup_service.dart';
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
      final downloadMessage = result.downloadPath != null
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

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isRestoring = true;
    });

    try {
      final restored = await BackupService.restoreDatabase();
      if (!mounted) {
        return;
      }
      if (restored == null) {
        return;
      }

      await context.read<TransactionProvider>().loadTransactions();
      await context.read<TransactionProvider>().loadDeletedTransactions();
      await context.read<ProductProvider>().loadProducts();
      await context.read<CategoryProvider>().loadCategories();
      await context.read<ProductionProvider>().loadTodayProduction();
      context.read<TransactionProvider>().markRestored();

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
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
        );
      },
      onManageUsers: isOwner
          ? () async {
              await context.read<UserProvider>().loadUsers();
              if (!context.mounted) {
                return;
              }
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ManageUsersScreen(),
                ),
              );
            }
          : null,
      onBackup: isOwner ? _backupDatabase : null,
      isBackingUp: _isBackingUp,
      onRestore: isOwner ? _restoreDatabase : null,
      isRestoring: _isRestoring,
    );
  }
}
