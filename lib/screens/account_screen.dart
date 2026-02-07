import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/account_panel.dart';
import 'login_screen.dart';
import 'manage_users_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

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
    );
  }
}
