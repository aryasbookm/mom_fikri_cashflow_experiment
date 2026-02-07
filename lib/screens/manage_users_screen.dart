import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../providers/user_provider.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadUsers();
    });
  }

  Future<void> _showAddStaffDialog(BuildContext context) async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tambah Staff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ],
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
        );
      },
    );

    if (result != true) {
      return;
    }

    final username = usernameController.text.trim();
    final password = passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username dan password wajib diisi')),
      );
      return;
    }

    final success = await context.read<UserProvider>().createStaff(
          username: username,
          password: password,
        );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(success ? 'Staff berhasil ditambahkan' : 'Username sudah ada'),
      ),
    );
  }

  Future<void> _showEditUsernameDialog(BuildContext context, User user) async {
    final usernameController = TextEditingController(text: user.username);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ubah Username'),
          content: TextField(
            controller: usernameController,
            decoration: const InputDecoration(labelText: 'Username'),
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
        );
      },
    );

    if (result != true) {
      return;
    }

    final username = usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username wajib diisi')),
      );
      return;
    }

    final success = await context.read<UserProvider>().updateUsername(
          userId: user.id!,
          username: username,
        );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(success ? 'Username diperbarui' : 'Username sudah digunakan'),
      ),
    );
  }

  Future<void> _confirmResetPassword(BuildContext context, User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset Password'),
          content: const Text(
            'Reset password staff menjadi "123456"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await context.read<UserProvider>().resetPassword(userId: user.id!);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password staff telah direset')),
    );
  }

  Future<void> _confirmDeleteUser(BuildContext context, User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Akun'),
          content: const Text('Akun ini akan dihapus permanen. Lanjutkan?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final success =
        await context.read<UserProvider>().deleteUserIfNoTransactions(user.id!);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Akun berhasil dihapus'
              : 'Akun tidak bisa dihapus karena ada transaksi',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color(0xFF8D1B3D);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Pengguna'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: themeColor,
        onPressed: () => _showAddStaffDialog(context),
        child: const Icon(Icons.add),
      ),
      body: Consumer<UserProvider>(
        builder: (context, provider, _) {
          if (provider.users.isEmpty) {
            return const Center(
              child: Text('Belum ada pengguna'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final user = provider.users[index];
              final isOwner = user.role == 'owner';
              final profilePath = user.profileImagePath;
              final file = (profilePath != null && profilePath.isNotEmpty)
                  ? File(profilePath)
                  : null;
              final imageProvider =
                  file != null && file.existsSync() ? FileImage(file) : null;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: themeColor.withOpacity(0.2),
                  backgroundImage: imageProvider,
                  child: imageProvider == null
                      ? Icon(
                          isOwner ? Icons.verified_user : Icons.person,
                          color: themeColor,
                        )
                      : null,
                ),
                title: Text(user.username),
                subtitle: Text(isOwner ? 'Owner' : 'Staff'),
                trailing: isOwner
                    ? const SizedBox.shrink()
                    : PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showEditUsernameDialog(context, user);
                          } else if (value == 'reset') {
                            _confirmResetPassword(context, user);
                          } else if (value == 'delete') {
                            _confirmDeleteUser(context, user);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Ubah Username'),
                          ),
                          PopupMenuItem(
                            value: 'reset',
                            child: Text('Reset Password'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Hapus Akun'),
                          ),
                        ],
                      ),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 24),
            itemCount: provider.users.length,
          );
        },
      ),
    );
  }
}
