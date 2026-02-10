# Changelog

All notable changes to this project will be documented in this file.

## [v1.0.0-rc3] - 2026-02-10 (Experimental #3)
*Fokus: Keamanan Data & Penyempurnaan UX*

### Added
- Sistem Backup & Restore robust (rollback + validasi versi + validasi struktur).
- Restore epoch untuk reset state otomatis setelah restore.
- PIN guard tab Akun (session 5 menit, PIN fleksibel).
- Opsi Logout/Ganti Akun dari dialog PIN (dengan konfirmasi).
- Top Produk (7 hari) di dashboard owner.

### Changed
- UI menu Akun dirombak menjadi grouped sections (Profil, Administrasi, Data & Keamanan).
- Android file picker untuk restore memakai `FileType.any` + validasi manual `.db`.

### Fixed
- Deadlock akses saat staff perlu logout dari akun owner yang terkunci PIN.

---

## [v1.0.0-rc2] - 2026-02-10 (Experimental #2)
*Fokus: Smart Inventory & Optimalisasi Transaksi*

### Added
- Multi-item transaction (keranjang belanja) + tabel `transaction_items`.
- Export Excel & PDF itemized (rincian item per transaksi).
- Target harian opsional (progress + confetti).
- Smart inventory control: `min_stock`, `is_active`, bulk aktif/arsip, low-stock alert toggle, auto-activate saat stok masuk.
- Dropdown alasan pengurangan stok + catatan opsional.
- Timestamp transaksi penuh (tanggal + jam).

### Changed
- Kasir hanya menampilkan produk aktif dengan stok > 0.
- Laporan PDF menampilkan jam transaksi.

### Fixed
- Perbaikan format tanggal/jam pada export agar konsisten.

---

## [v1.0.0-rc1] - 2026-02-10 (Experimental #1)
*Fokus: Audit Trail & Manajemen Akun*

### Added
- Manajemen akun: CRUD staff, reset password, ganti password & foto profil.
- Audit trail penghapusan transaksi (alasan wajib), audit log owner, restore, hapus permanen.
- Export Excel dari Riwayat (sesuai filter aktif) dengan format rupiah + tabel.
- Laporan: tren 7 hari, pie chart pemasukan/pengeluaran, export PDF keuangan + waste.
- Struk digital: detail item transaksi + share struk gambar.
- Backup & restore DB dengan validasi versi/struktur + rollback (baseline fitur).

### Changed
- Penyimpanan password user menjadi hash (SHA-256).
- Transaksi menyimpan timestamp lengkap (tanggal + jam).
- UI Akun ditata ulang jadi grouped sections.

### Fixed
- Refresh audit log agar item langsung hilang setelah restore/delete.
- Isolasi transaksi staff (hindari data admin muncul di akun staff).
- Error akses foto profil di macOS dengan menyalin file ke app storage.

### Security
- Audit trail persisten di SQLite untuk semua penghapusan transaksi staff.
- Owner-only audit log dengan restore/hapus permanen.
- PIN guard untuk akses tab Akun owner.

---

## [v0.9.0] - 2026-02-10 (Base Version / Cashflow Utama)
*Fokus: Core POS & Manajemen Stok Dasar*

### Added
- Sistem stok terintegrasi: produksi menambah stok, penjualan & waste mengurangi stok.
- Produk baru bisa ditambahkan (nama + harga).
- Grid kasir dengan validasi stok + ringkasan transaksi sebelum simpan.
- Laporan keuangan dengan toggle pemasukan/pengeluaran dan navigasi bulan.
- Riwayat transaksi dengan filter waktu + ringkasan (masuk/keluar/saldo).
- Log barang rusak/basi harian di halaman produksi.
- Dashboard owner dengan ringkasan harian dan total stok tersedia.

### Changed
- Dashboard owner menggunakan kartu keuangan gabungan (saldo + pemasukan/pengeluaran).
- Staff dashboard ditata ulang: tab Beranda, Stok, Akun.
- Produk di grid kasir diurutkan stok > 0 di atas, lalu alfabetis.
- Produksi menampilkan stok produk dan daftar produksi harian (accordion).

### Fixed
- Validasi penjualan agar stok tidak bisa minus.
- Undo transaksi pemasukan mengembalikan stok.
- Transaksi `WASTE` tidak ikut perhitungan kas harian/riwayat kas.

### Security
- Staff tidak dapat melihat laporan keuangan (owner-only).
