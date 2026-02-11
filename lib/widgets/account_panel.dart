import 'dart:io';

import 'package:flutter/foundation.dart';
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
    this.onBackup,
    this.isBackingUp = false,
    this.onRestore,
    this.isRestoring = false,
    this.onDebugSimulateBackup,
    this.autoBackupEnabled = true,
    this.onToggleAutoBackup,
    this.onTestCloudConnection,
    this.isTestingCloud = false,
    this.onRestoreCloudBackup,
    this.isRestoringCloud = false,
    this.cloudBackupInfoText,
    this.onCloudAccountAction,
    this.isCloudAccountActionInProgress = false,
    this.isCloudAccountConnected = false,
  });

  final VoidCallback onLogout;
  final VoidCallback? onManageUsers;
  final VoidCallback? onBackup;
  final bool isBackingUp;
  final VoidCallback? onRestore;
  final bool isRestoring;
  final VoidCallback? onDebugSimulateBackup;
  final bool autoBackupEnabled;
  final ValueChanged<bool>? onToggleAutoBackup;
  final VoidCallback? onTestCloudConnection;
  final bool isTestingCloud;
  final VoidCallback? onRestoreCloudBackup;
  final bool isRestoringCloud;
  final String? cloudBackupInfoText;
  final VoidCallback? onCloudAccountAction;
  final bool isCloudAccountActionInProgress;
  final bool isCloudAccountConnected;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Foto profil diperbarui')));
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
      final fileName =
          'profile_${DateTime.now().millisecondsSinceEpoch}$extension';
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
                decoration: const InputDecoration(labelText: 'Password Baru'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Semua field wajib diisi')));
      return;
    }

    if (newPin != confirmPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konfirmasi password tidak cocok')),
      );
      return;
    }

    final success = await context.read<AuthProvider>().changePassword(
      currentPin: currentPin,
      newPin: newPin,
    );
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileCard(
            imageProvider: imageProvider,
            username: user?.username ?? 'Pengguna',
            role: user?.role ?? '-',
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Pengaturan Akun'),
          _SectionCard(
            children: [
              _SettingsTile(
                icon: Icons.photo_camera_outlined,
                label: 'Ganti Foto',
                onTap: () => _pickProfileImage(context),
              ),
              _SettingsTile(
                icon: Icons.lock_reset,
                label: 'Ganti Password',
                onTap: () => _changePassword(context),
              ),
            ],
          ),
          if (onManageUsers != null) ...[
            const SizedBox(height: 16),
            const _SectionTitle(title: 'Administrasi'),
            _SectionCard(
              children: [
                _SettingsTile(
                  icon: Icons.manage_accounts,
                  label: 'Kelola Pengguna',
                  onTap: onManageUsers,
                ),
              ],
            ),
          ],
          if (onBackup != null || onRestore != null) ...[
            const SizedBox(height: 16),
            const _SectionTitle(title: 'Data & Keamanan'),
            _SectionCard(
              children: [
                if (onToggleAutoBackup != null)
                  _SwitchTile(
                    icon: Icons.backup_outlined,
                    label: 'Auto-backup Lokal',
                    value: autoBackupEnabled,
                    onChanged: onToggleAutoBackup!,
                  ),
                if (onBackup != null)
                  _SettingsTile(
                    icon: Icons.cloud_upload_outlined,
                    label: isBackingUp ? 'Membuat Backup...' : 'Backup Data',
                    onTap: isBackingUp ? null : onBackup,
                    trailing:
                        isBackingUp
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : null,
                  ),
                if (onRestore != null)
                  _SettingsTile(
                    icon: Icons.settings_backup_restore,
                    label: isRestoring ? 'Memulihkan Data...' : 'Restore Data',
                    onTap: isRestoring ? null : onRestore,
                    trailing:
                        isRestoring
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : null,
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Catatan: backup .zip menyertakan foto produk. Jika restore dari file .db lama, foto produk tidak ikut dipulihkan.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (onTestCloudConnection != null ||
              onRestoreCloudBackup != null ||
              onCloudAccountAction != null ||
              (kDebugMode && onDebugSimulateBackup != null)) ...[
            const SizedBox(height: 16),
            const _SectionTitle(title: 'Cloud & Debug'),
            _SectionCard(
              children: [
                if (onTestCloudConnection != null)
                  _SettingsTile(
                    icon: Icons.cloud_done_outlined,
                    label:
                        isTestingCloud
                            ? 'Backup ke Cloud...'
                            : 'Backup ke Google Drive',
                    onTap: isTestingCloud ? null : onTestCloudConnection,
                    trailing:
                        isTestingCloud
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : null,
                  ),
                if (cloudBackupInfoText != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      cloudBackupInfoText!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ),
                if (onRestoreCloudBackup != null)
                  _SettingsTile(
                    icon: Icons.cloud_download_outlined,
                    label:
                        isRestoringCloud
                            ? 'Restore dari Cloud...'
                            : 'Restore dari Google Drive',
                    onTap: isRestoringCloud ? null : onRestoreCloudBackup,
                    trailing:
                        isRestoringCloud
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : null,
                  ),
                if (onCloudAccountAction != null)
                  _SettingsTile(
                    icon:
                        isCloudAccountConnected
                            ? Icons.logout_outlined
                            : Icons.login_outlined,
                    label:
                        isCloudAccountActionInProgress
                            ? 'Memproses Akun...'
                            : (isCloudAccountConnected
                                ? 'Ganti Akun Google Drive'
                                : 'Hubungkan Akun Google Drive'),
                    onTap:
                        isCloudAccountActionInProgress
                            ? null
                            : onCloudAccountAction,
                    trailing:
                        isCloudAccountActionInProgress
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : null,
                  ),
                if (kDebugMode && onDebugSimulateBackup != null)
                  // DEBUG ONLY: Hapus sebelum rilis.
                  _SettingsTile(
                    icon: Icons.bug_report_outlined,
                    label: '[DEV] Simulasi Lupa Backup (4 Hari)',
                    onTap: onDebugSimulateBackup,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onLogout,
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.imageProvider,
    required this.username,
    required this.role,
  });

  final ImageProvider? imageProvider;
  final String username;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: const Color(0xFFE0E0E0),
            backgroundImage: imageProvider,
            child:
                imageProvider == null
                    ? const Icon(Icons.person, size: 32, color: Colors.white70)
                    : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(role, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Color(0xFF8D1B3D),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        tiles.add(const Divider(height: 1));
      }
      tiles.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: tiles),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF8D1B3D)),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: disabled ? Colors.grey : Colors.black87,
        ),
      ),
      trailing:
          trailing ?? const Icon(Icons.chevron_right, color: Colors.black45),
      onTap: onTap,
      enabled: !disabled,
      dense: false,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: const Color(0xFF8D1B3D)),
      title: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      value: value,
      onChanged: (value) => onChanged(value),
    );
  }
}
