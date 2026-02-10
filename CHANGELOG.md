# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-10

### Added
**Core Features & Transactions**
- Multi-item transaction (keranjang belanja) dengan tabel `transaction_items`.
- Fitur Struk Digital: rincian transaksi + share gambar struk ke WhatsApp/Sosmed.
- Target Harian (Omzet) dengan progress bar visual dan efek confetti saat tercapai.
- Timestamp transaksi lengkap (tanggal + jam) untuk akurasi laporan.

**Inventory Management**
- Smart Inventory Control: status aktif/arsip, alert stok menipis, dan aktivasi otomatis saat stok masuk.
- Audit Trail Pengurangan Stok: dropdown alasan (Rusak, Kadaluwarsa, Konsumsi) + catatan opsional.

**Data Management & Security**
- Sistem Backup & Restore Robust:
    - Backup ke file `.db` (share/simpan lokal).
    - Restore dengan validasi versi database, validasi struktur, dan rollback otomatis jika gagal.
    - Restore Epoch: reset state aplikasi otomatis setelah restore berhasil.
- PIN Guard Security:
    - Kunci akses menu Akun/Admin (session 5 menit).
    - Mendukung PIN panjang variabel.
    - Opsi "Logout/Ganti Akun" langsung dari layar kunci PIN (mencegah deadlock).
- Audit Log Owner: pencatatan aktivitas penghapusan transaksi sensitif.

**Reporting & Exports**
- Dashboard Owner Baru: Ringkasan Harian + Top Produk (7 Hari) + Alert Stok.
- Export Laporan Lengkap:
    - Excel: Format rupiah rapi, rincian item per transaksi (itemized).
    - PDF: Laporan keuangan harian/bulanan + laporan waste.

**Account Management**
- CRUD Management untuk akun Staff (Tambah/Edit/Hapus).
- Isolasi Data: Staff hanya melihat transaksinya sendiri, Owner melihat global.

### Changed
- UI Menu Akun dirombak total menjadi Grouped Sections (Profil, Administrasi, Data & Keamanan) untuk UX yang lebih baik.
- Password user kini disimpan menggunakan hashing (SHA-256) untuk keamanan standar.
- Logika Kasir: Hanya menampilkan produk dengan status `is_active = 1` dan stok > 0.

### Fixed
- **Critical**: Perbaikan deadlock akses saat staff ingin logout dari akun owner yang terkunci PIN.
- **System**: Perbaikan permission file picker pada Android 13+ (menggunakan `FileType.any` dengan validasi manual).
- **System**: Perbaikan permission printing/akses file pada macOS (entitlements).
- **Bug**: Refresh audit log agar item langsung hilang dari list setelah dihapus.
- **Bug**: Koreksi validasi stok agar tidak bisa minus saat transaksi.

### Security
- Penerapan "Owner-Only Scope" pada laporan keuangan dan fitur backup.
- Penyimpanan password hash dan validasi PIN berlapis.
