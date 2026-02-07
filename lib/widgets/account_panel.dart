import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class AccountPanel extends StatelessWidget {
  const AccountPanel({
    super.key,
    required this.onLogout,
    this.onManageUsers,
  });

  final VoidCallback onLogout;
  final VoidCallback? onManageUsers;

  Future<void> _pickProfileImage(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null) {
      return;
    }
    final savedPath = await _copyToAppStorage(image);
    if (savedPath == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menyimpan foto profil')),
        );
      }
      return;
    }
    await context.read<AuthProvider>().updateProfileImagePath(savedPath);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto profil diperbarui')),
      );
    }
  }

  Future<String?> _copyToAppStorage(XFile image) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(directory.path, 'profile_images'));
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }
      final extension = p.extension(image.path);
      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}$extension';
      final targetPath = p.join(targetDir.path, fileName);
      final savedFile = await File(image.path).copy(targetPath);
      return savedFile.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ganti Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password Saat Ini',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password Baru',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Konfirmasi Password Baru',
                ),
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

    final currentPin = currentController.text.trim();
    final newPin = newController.text.trim();
    final confirmPin = confirmController.text.trim();

    if (newPin.isEmpty || currentPin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua field wajib diisi')),
      );
      return;
    }

    if (newPin != confirmPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konfirmasi password tidak cocok')),
      );
      return;
    }

    final success = await context
        .read<AuthProvider>()
        .changePassword(currentPin: currentPin, newPin: newPin);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Password berhasil diubah' : 'Password saat ini salah',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final profilePath = user?.profileImagePath;
    File? file;
    if (profilePath != null && profilePath.isNotEmpty) {
      try {
        final candidate = File(profilePath);
        if (candidate.existsSync()) {
          file = candidate;
        }
      } catch (_) {
        file = null;
      }
    }
    final imageProvider = file != null ? FileImage(file) : null;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: const Color(0xFFE0E0E0),
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? const Icon(Icons.person, size: 48, color: Colors.white70)
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            user?.username ?? 'Pengguna',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            user?.role ?? '-',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8D1B3D),
              foregroundColor: Colors.white,
            ),
            onPressed: () => _pickProfileImage(context),
            icon: const Icon(Icons.photo_camera),
            label: const Text('Ganti Foto'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _changePassword(context),
            icon: const Icon(Icons.lock_reset),
            label: const Text('Ganti Password'),
          ),
          if (onManageUsers != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onManageUsers,
              icon: const Icon(Icons.manage_accounts),
              label: const Text('Kelola Pengguna'),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            onPressed: onLogout,
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
