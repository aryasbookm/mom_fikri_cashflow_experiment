> **Tentang:** Riwayat perubahan versi dan fitur proyek secara kronologis.
> **Audiens:** Developer, penguji, reviewer rilis.
> **Konteks:** Dipakai untuk tracking evolusi fitur, regression check, dan bukti progres skripsi.

# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - Phase 4
*Fokus: Pencarian Global, Reminder Backup, Insight Produk Lambat*

### Added
- Global Search: search bar di Kasir, Stok, dan Riwayat dengan filtering real-time.
- Deep Search Riwayat: pencarian juga mencakup nama produk dari transaksi multi-item.
- Foto produk opsional berbasis filesystem lokal (`product_images/prod_{id}.jpg`) dengan picker galeri/kamera.
- Smart Backup Reminder + catatan rencana auto-backup lokal (toggle + retention) dan cloud backup fase berikutnya.
- Debug owner: tombol simulasi lupa backup (mundurkan timestamp 4 hari).
- Slow Moving Analytics: tampilkan 3–5 produk dengan penjualan terendah (30 hari terakhir) untuk insight operasional.
- Auto-backup lokal: otomatis saat app paused dengan throttle 5 menit + guard perubahan data, simpan 5 file terakhir.
- Restore dua jalur: file manual (file picker) dan auto-backup list internal.
- Cloud Backup Android: upload backup `.zip` ke Google Drive `appDataFolder`.
- Cloud Restore Android: pulihkan database dari backup cloud terbaru (`appDataFolder`).
- Cloud Restore Picker Android: restore dari file cloud terpilih (bukan hanya latest) via bottom sheet list.
- Cloud Metadata UI: tampilkan "Terakhir Backup Cloud" berdasarkan timestamp lokal backup cloud terakhir.
- Backup format v2: paket `.zip` berisi database + folder `product_images` + metadata manifest.
- Hybrid backup mode (manual): pilih **Data Only** (DB saja) atau **Full** (DB + foto produk), dengan flag `includeImages` di `manifest.json`.
- Auto-Backup Cloud (opsional): owner-only, default OFF, data-only, maksimal 1x/24 jam, dan hanya saat ada perubahan data.
- Akun: section backup kini konsisten menjadi **Backup Lokal / Backup Cloud / Pengaturan Google Drive**.
- Produksi: filter daftar stok **Aktif / Arsip / Semua** (default: Aktif).
- Guarded delete produk: hapus permanen hanya diizinkan jika stok `0` dan belum punya riwayat di `transaction_items`.

### Changed
- Branding aplikasi disederhanakan dari "Toko Kue Mom Fiqry (Eksperimen)" menjadi "Toko Kue Mom Fiqry" pada Android/iOS/Web/Desktop.
- Folder kerja proyek diganti dari `mom_fikri_cashflow_experiment` menjadi `mom_fiqry_cashflow_experiment`.
- Dashboard owner: ringkasan harian statis, analitik produk foldable default terbuka.
- Dashboard owner empty-state: banner backup dan kartu/toggle peringatan stok disembunyikan saat aplikasi masih fresh install (belum ada data operasional).
- Cloud backup sukses kini ikut memperbarui metadata backup global, sehingga pengingat backup dashboard sinkron untuk backup lokal maupun cloud.
- Riwayat: result counter dan subtitle match saat pencarian aktif.
- Smart Backup: reminder dan auto-backup hanya berjalan jika ada perubahan data sejak backup terakhir.
- Menu debug Akun: tombol cloud sekarang melakukan backup/restore Google Drive (Android).
- Validasi fitur cloud dilakukan di Android; kendala keychain/signing macOS dicatat sebagai batasan environment development.
- UX cloud: pesan error jaringan dibuat lebih ramah pengguna (tanpa detail exception teknis).
- Kasir (pemasukan): kartu grid produk kini memakai vertical stack responsif dengan thumbnail rounded agar hierarki visual lebih rapat.
- Kasir (pemasukan): fine-tuning visual akhir pada kartu grid:
  - format harga tanpa desimal (contoh `Rp 15.000`),
  - avatar produk diperbesar proporsional (`(tileWidth * 0.15).clamp(28, 52)`),
  - penekanan harga ditingkatkan (font lebih menonjol).
- Restore cloud: daftar backup menandai item terbaru dengan badge "Terbaru".
- Cloud account: aksi akun cloud kini adaptif:
  - saat belum login tampil "Hubungkan Akun Google Drive",
  - saat sudah login tampil "Ganti Akun Google Drive" dengan dialog konfirmasi sebelum disconnect dan re-login.
- UI backup menampilkan catatan kompatibilitas restore (`.zip` termasuk foto, `.db` lama tanpa foto).
- Backup lokal/cloud kini menggunakan file `.zip` agar foto produk ikut tersimpan.
- Restore kini kompatibel dua format:
  - `.zip` memulihkan database + foto produk,
  - `.db` lama tetap didukung (database only, tanpa foto).
- Operasional repo: ditambahkan `WORKFLOW.md` + konvensi `.env` `PORT=3010` untuk fixed-port workflow dan recovery cepat.
- Restore hybrid mode:
  - jika backup `includeImages=true`, restore mengganti database + folder foto produk,
  - jika backup `includeImages=false`, restore hanya mengganti database dan mempertahankan foto lokal.
- Seed produk awal kini default **arsip** (`is_active=0`) dengan `min_stock=5`; produk arsip auto-aktif saat stok bertambah.
- UI Akun backup:
  - urutan item lokal/cloud diseragamkan menjadi **Auto-Backup -> Cadangkan -> Pulihkan**,
  - catatan backup panjang dibuat foldable lewat panel **Info & Catatan Penting** (default tertutup).
- Kasir (catat pemasukan): saat produk yang sama dipilih ulang, input jumlah kini memperbarui qty item di cart (replace), bukan menambah qty lama.

---

## [v1.0.0-rc3] - 2026-02-10 (Experimental #3)
*Fokus: Keamanan Data & Penyempurnaan UX*

### Added
- Sistem Backup & Restore robust (rollback + validasi versi + validasi struktur).
- Restore epoch untuk reset state otomatis setelah restore.
- PIN guard tab Akun (session 5 menit, PIN fleksibel).
- Opsi Logout/Ganti Akun dari dialog PIN (dengan konfirmasi).
- Top Produk (7 hari) di dashboard owner.

### Changed
- UI menu Akun dirombak menjadi grouped sections terstruktur.
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
