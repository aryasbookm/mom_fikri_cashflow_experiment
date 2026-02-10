# Project Notes — Toko Kue Mom Fiqry (Eksperimen)

## Ringkasan
- **Nama aplikasi (label & UI):** Toko Kue Mom Fiqry (Eksperimen)
- **Tujuan:** Cashflow + stok terintegrasi untuk UMKM toko kue.
- **Platform:** Flutter (Android + desktop macOS untuk dev)
- **DB:** SQLite (`sqflite`)
- **State:** Provider
- **Release Notes:** lihat `CHANGELOG.md` (timeline v0.9.0 → v1.0.0-rc3)

## Rencana Experimental #4 (Final)
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
   - Cloud backup (Drive) lebih aman untuk kehilangan HP, tetapi kompleks (fase berikutnya).
   - Debug owner: tombol simulasi lupa backup (mundurkan timestamp 4 hari).
   - Auto-backup lokal: berjalan saat app paused, maksimal 1x/24 jam, simpan 5 file terakhir di `auto_backups/`.
   - Deteksi perubahan data memakai snapshot jumlah transaksi + produk + audit log.
3. **Slow Moving Analytics**
   - Tampilkan 3–5 produk dengan penjualan terendah (7–30 hari terakhir).
   - Fokus insight operasional: kurangi produksi barang lambat.
   - Dashboard: Ringkasan Hari Ini statis, analitik produk foldable default terbuka.

Catatan:
- Peak Hours ditunda.
- Stock Opname ditunda ke fase berikutnya.

## Fitur Utama
1. **Login Role**
   - Owner: akses penuh
   - Staff: operasional (Beranda, Stok, Akun)
   - Seed user: admin/1234 (owner), karyawan/0000 (staff)
   - Password disimpan dalam bentuk hash (SHA-256)
   - Tab Akun untuk owner dilindungi PIN (session 5 menit, panjang PIN fleksibel)
   - Dialog PIN menyediakan opsi Logout/Ganti Akun dengan konfirmasi

2. **Pemasukan (Kasir)**
   - Grid produk → tambah ke keranjang (multi-item)
   - Validasi stok per item
   - Manual input tetap ada
   - Ringkasan total otomatis

3. **Pengeluaran**
   - Input manual
   - Kategori bisa tambah via opsi **Lainnya**

4. **Produksi & Stok**
   - Produksi menambah stok
   - Penjualan & waste mengurangi stok
   - Produk baru bisa ditambah (nama + harga)
   - Waste dicatat sebagai transaksi `type='WASTE'`

5. **Riwayat Transaksi (Owner)**
   - Filter waktu: Hari Ini, Kemarin, 7 Hari, Bulan Ini, Semua
   - Summary (Masuk/Keluar/Saldo) sesuai filter
   - Delete transaksi → pemasukan dikembalikan stok
   - Export Excel dari Riwayat (sesuai filter aktif)

6. **Laporan**
   - Grafik tren 7 hari (pemasukan vs pengeluaran)
   - Pie chart pemasukan/pengeluaran (toggle)
   - Navigasi bulan (prev/next)
   - Ringkasan waste bulanan (qty saja)
   - Export PDF laporan bulanan (keuangan + waste)

7. **Struk Digital**
   - Detail transaksi menampilkan item (dari `transaction_items`)
   - Bagikan struk sebagai gambar (share)

7. **Manajemen Akun & Audit**
   - Owner dapat kelola staff (CRUD, reset password)
   - User dapat ganti foto profil & password
   - Penghapusan transaksi oleh staff wajib isi alasan (Audit Trail)
   - Owner dapat melihat, restore, atau hapus permanen audit log

8. **Backup & Restore (Robust)**
   - Backup DB ke file `.db` (share + simpan ke Download)
   - Restore via file picker (Android pakai `FileType.any`) dengan rollback, validasi versi, dan validasi struktur
   - Restore memicu refresh data + reset filter laporan/riwayat

9. **Dashboard Owner (Ringkas)**
   - Menampilkan Top Produk (7 hari) untuk keputusan produksi

## Skema Database (v8)
- **products**: id, name (unique), price, stock, min_stock, is_active
- **transactions**: id, type, amount, category_id, description, date, user_id, product_id, quantity
- **transaction_items**: id, transaction_id, product_id, product_name, unit_price, quantity, total
- **production**, **categories**, **users** (users memiliki `profile_image_path`)
- **deleted_transactions**: log penghapusan transaksi (alasan, waktu, pelaku, item terkait)
  - Kolom tambahan: category_id, user_id, product_id, quantity

`type` transaksi:
- `IN` pemasukan
- `OUT` pengeluaran
- `WASTE` stok dibuang (amount 0)

## File Kunci
- UI:
  - `lib/screens/owner_dashboard.dart`
  - `lib/screens/staff_dashboard.dart`
  - `lib/screens/add_transaction_screen.dart`
  - `lib/screens/production_screen.dart`
  - `lib/screens/history_screen.dart`
  - `lib/screens/report_screen.dart`
  - `lib/screens/transaction_detail_screen.dart`
  - `lib/screens/manage_users_screen.dart`
- Provider:
  - `lib/providers/transaction_provider.dart`
  - `lib/providers/product_provider.dart`
  - `lib/providers/production_provider.dart`
  - `lib/providers/category_provider.dart`
  - `lib/providers/auth_provider.dart`
  - `lib/providers/user_provider.dart`
- Services:
  - `lib/services/export_service.dart` (Excel)
  - `lib/services/pdf_service.dart` (PDF)
  - Export Excel & PDF sudah itemized (rincian item per transaksi)

## Catatan UI/UX
- Login: gradient maroon + card modern
- Produk grid diurutkan: stok > 0 di atas, lalu alfabetis
- Owner dashboard: combo card saldo + mini pemasukan/pengeluaran
- Target harian opsional (progress + confetti) di header dashboard
- Transaksi sekarang menyimpan timestamp lengkap (tanggal + jam)
- Akun: tampilan grouped sections (Pengaturan, Administrasi, Data & Keamanan)
  - Style: ListTile + card sections (lebih rapat & terstruktur)

## Build & Icon
- Icon: `assets/icon_toko.png`
- `flutter_launcher_icons` sudah ada di `pubspec.yaml`
- Jalankan manual:
  ```bash
  flutter pub get
  flutter pub run flutter_launcher_icons
  ```

## Reset DB (Hard Reset)
- DB version: 8
- File DB: `mom_fikri_cashflow_v2.db`
- Naikkan versi di `DatabaseHelper` jika perlu reset ulang

## Validasi Stok (kasir)
```dart
final product = productProvider.getById(productId);
final available = product?.stock ?? 0;
if (quantity > available) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Stok tidak cukup! Sisa: $available')),
  );
  return;
}
```
