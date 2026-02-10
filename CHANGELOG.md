# Changelog

All notable changes to this project will be documented in this file.

## 2026-02-10
### Added
- Backup database ke file `.db` (share + simpan ke Download).
- Restore database dengan rollback, validasi versi, dan validasi struktur.
- Reset filter laporan/riwayat otomatis setelah restore (restore epoch).
- PIN guard tab Akun (session 5 menit) dengan PIN panjang variabel.
- Opsi Logout/Ganti Akun dari dialog PIN (dengan konfirmasi).
- Top Produk (7 hari) di dashboard owner.
- Dokumen UAT: `TESTING_BACKUP_RESTORE.md`.

### Changed
- UI menu Akun dirombak menjadi grouped sections berbasis ListTile.
- Android file picker untuk restore menggunakan `FileType.any` (validasi `.db` manual).

### Fixed
- Perbaikan deadlock akses dengan menyediakan logout tanpa PIN di dialog (tetap ada konfirmasi).
