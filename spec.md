# SPESIFIKASI PROYEK: TOKO KUE MOM FIQRY

## 1. Identitas Aplikasi
- **Nama:** Toko Kue Mom Fiqry
- **Tujuan:** Digitalisasi pencatatan keuangan & stok toko kue (menggantikan buku manual).
- **Platform:** Android (Mobile) + pengembangan di desktop.
- **Sifat:** Offline-First (data disimpan lokal di perangkat).
- **Release Notes:** `CHANGELOG.md` (timeline v0.9.0 → v1.0.0-rc3)

## Rencana Fase 4 (Final)
Prioritas (tanpa ubah DB v8):
1. **Global Search**
   - Search bar di Kasir, Stok, dan Riwayat.
   - Filtering real-time saat mengetik.
   - Riwayat mendukung deep search (nama produk dari `transaction_items`).
   - Riwayat menampilkan result counter + subtitle match saat pencarian aktif.
2. **Smart Backup Reminder**
   - Tidak ada auto-backup background.
   - Simpan tanggal backup terakhir.
   - Banner/alert di Dashboard jika > 3 hari belum backup.
   - Banner hanya muncul jika sudah ada data (transaksi/produk).
   - Banner hanya muncul jika ada perubahan data sejak backup terakhir.
   - Catatan: auto-backup lokal saja tidak melindungi jika HP hilang; aman mulai dari reminder.
   - Jika auto-backup lokal ditambahkan: wajib toggle ON/OFF, retention 5–10 file terbaru, lokasi Download/App Documents.
   - Cloud backup (Drive) tersedia untuk Android: upload/restore paket `.zip` (database + foto produk) via Google Drive `appDataFolder`, kompatibel restore `.db` lama.
   - Catatan dev: pengujian macOS dapat terkendala keychain/signing environment (Personal Team).
   - Debug owner: tombol simulasi lupa backup (mundurkan timestamp 4 hari).
   - Auto-backup lokal: berjalan saat app paused, maksimal 1x/24 jam, simpan 5 file terakhir di `auto_backups/`.
   - Deteksi perubahan data memakai snapshot jumlah transaksi + produk + audit log.
   - Restore: dua jalur (manual file picker + auto-backup list internal).
3. **Slow Moving Analytics**
   - Tampilkan 3–5 produk dengan penjualan terendah (7–30 hari terakhir).
   - Fokus insight operasional: kurangi produksi barang lambat.
   - Dashboard: Ringkasan Hari Ini statis, analitik produk foldable default terbuka.

Catatan:
- Peak Hours ditunda.
- Stock Opname ditunda ke fase berikutnya.

## 2. Tech Stack (Wajib)
- **Framework:** Flutter (Dart).
- **Database:** SQLite (package `sqflite`).
- **State Management:** Provider.
- **UI Style:** Material Design 3, tema marun/krem (bakery).
- **Export PDF:** `pdf` + `printing`.
- **Gamifikasi:** `shared_preferences`, `percent_indicator`, `confetti`.
- **Struk Digital:** `screenshot` + `share_plus` + `path_provider`.
- **Export Itemized:** Excel/PDF menampilkan rincian item per transaksi.
- **Backup/Restore:** `file_picker` + `share_plus` + `path_provider`.
  - Android picker memakai `FileType.any` + validasi manual `.zip` / `.db`.
  - Cloud Android memakai `google_sign_in` + `googleapis` (folder `appDataFolder`).

## 2.1 Quality Gate (Engineering Process)
Setiap fitur non-trivial dinyatakan siap merge jika lolos:
1. **Happy Path** (alur normal sukses end-to-end).
2. **Edge Case** (minimal 1 skenario gagal ditangani aman).
3. **Rollback/Recovery** (tidak meninggalkan state parsial/korup saat gagal).

## 3. Aktor & Hak Akses
**Owner (Pemilik):**
- Bisa login.
- Bisa input transaksi (pemasukan/pengeluaran).
- Bisa input produksi & mengelola stok.
- Bisa melihat laporan (grafik) dan riwayat transaksi.
- Bisa hapus transaksi.
- Bisa kelola akun staff (tambah/ubah/hapus, reset password).
- Bisa melihat Audit Log, restore, dan hapus permanen log.
- Tab Akun dilindungi PIN owner (session 5 menit, panjang PIN fleksibel).
  - Dialog PIN menyediakan opsi Logout/Ganti Akun.
  - Logout dari dialog PIN memakai konfirmasi.

**Staff (Karyawan):**
- Bisa login.
- Bisa input transaksi & produksi untuk operasional.
- Bisa melihat beranda & stok, **tidak** bisa melihat laporan keuangan.
- Bisa menghapus transaksi miliknya dengan alasan (Audit Trail).

## 4. Struktur Database (Tabel)
1. **users:** id, username, pin (hash), role, profile_image_path.
2. **categories:** id, name, type (IN/OUT). Mendukung tambahan kategori via opsi “Lainnya”.
3. **products:** id, name, price, stock, min_stock, is_active.
4. **transactions:** id, type (IN/OUT/WASTE), amount, category_id, description, date, user_id, product_id, quantity.
5. **transaction_items:** id, transaction_id, product_id, product_name, unit_price, quantity, total.
6. **production:** id, product_name, quantity, date, user_id.
7. **deleted_transactions:** audit log penghapusan (original_id, type, amount, category_id, category, description, date, user_id, product_id, quantity, deleted_at, deleted_by, reason).

## 5. Modul Utama
- **Kasir (Pemasukan):** grid produk + input jumlah, validasi stok, ringkasan sebelum simpan.
  - Keranjang bersifat foldable (default tertutup) dengan sticky summary bar (`jumlah produk + total`) agar area pilih produk tetap luas.
- **Pengeluaran:** input manual, kategori dinamis.
- **Produksi & Stok:** produksi menambah stok, penjualan & waste mengurangi stok.
- **Produksi & Stok:** produksi menambah stok, penjualan & waste mengurangi stok.
  - Daftar stok memiliki filter tampilan `Aktif` (default), `Arsip`, `Semua`.
  - Seed produk awal disimpan dalam status arsip (`is_active=0`) untuk menghindari noise awal.
  - Produk arsip auto-aktif saat stok bertambah (`stock > 0`).
  - Hapus permanen produk hanya diizinkan jika `stock == 0` dan tidak ada referensi di `transaction_items`.
  - Jika syarat hapus permanen tidak terpenuhi, alur yang direkomendasikan adalah arsip/nonaktif.
- **Waste (Barang rusak/basi):** dicatat sebagai transaksi `WASTE` (amount 0).
- **Laporan:** grafik tren 7 hari, pie chart pemasukan/pengeluaran, toggle tipe, navigasi bulan, export PDF (keuangan + waste).
- **Struk Digital:** detail transaksi + bagikan struk (gambar) dari transaksi pemasukan.
- **Target Harian (Owner):** opsional, progress bar omzet harian + confetti saat tercapai.
- **Timestamp Transaksi:** simpan tanggal + jam untuk analisa jam sibuk.
- **Riwayat:** filter waktu (hari ini/kemarin/7 hari/bulan ini/semua), summary masuk/keluar/saldo, hapus transaksi, export Excel.
- **Audit Log:** melihat transaksi yang dihapus, restore, hapus permanen.
- **Backup & Restore:** backup `.zip` (database + foto produk) dengan share/download, restore rollback-safe + validasi versi/struktur. Restore `.db` lama tetap didukung (database only).
- **Cloud Backup Android:** upload paket backup (`.zip`) ke Google Drive (`appDataFolder`).
- **Cloud Restore Android:** pilih file backup cloud dari daftar (nama, tanggal, ukuran) lalu restore aman untuk `.zip` maupun `.db` lama.
- **Cloud Visibility:** UI menampilkan metadata lokal "Terakhir Backup Cloud" dari timestamp backup cloud terakhir.
- **Cloud UX Polish:** item backup terbaru ditandai badge "Terbaru", error jaringan ditampilkan sebagai pesan ramah pengguna, dan tersedia opsi "Ganti Akun Google Drive" (disconnect).
- **PIN Guard:** tab Akun meminta PIN owner, sesi 5 menit.
  - UI PIN mendukung panjang PIN variabel (submit manual).
  - Dialog PIN menyediakan opsi Logout/Ganti Akun (dengan konfirmasi).
- **Dashboard Owner:** menampilkan Top Produk (7 hari) sebagai info operasional.

## 6. Alur Utama
- Buka aplikasi → Login → cek role.
- Owner: Dashboard dengan saldo, stok tersedia, ringkasan hari ini, tombol aksi (pemasukan/pengeluaran/riwayat).
- Staff: Beranda (transaksi hari ini + total setoran), tab Stok, tab Akun.

## 6.1 Skenario Uji Produksi & Aset
- **Guarded Delete (Happy Path):**
  - Produk stok 0, belum pernah terjual -> dapat dihapus permanen.
- **Guarded Delete (Edge Case):**
  - Produk stok > 0 -> hapus permanen ditolak.
  - Produk stok 0 tapi pernah dipakai transaksi -> hapus permanen ditolak.
- **Filter View:**
  - `Aktif/Arsip/Semua` hanya memengaruhi daftar tampilan di layar produksi.
- **Konsistensi Aset Stok:**
  - Perubahan filter tampilan produksi tidak boleh mengubah perhitungan total stok global/dashboard.

## 7. Data Awal (Seeding)
- User default: admin/1234 (owner), karyawan/0000 (staff).
- Kategori awal: Penjualan Kue (IN), Bahan Baku/Operasional/Gaji (OUT).
- Produk awal: daftar kue dan snack sesuai data seed (dengan harga, stok awal 0).
