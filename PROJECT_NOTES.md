# Project Notes — Toko Kue Mom Fiqry (Eksperimen)

## Ringkasan
- **Nama aplikasi (label & UI):** Toko Kue Mom Fiqry (Eksperimen)
- **Tujuan:** Cashflow + stok terintegrasi untuk UMKM toko kue.
- **Platform:** Flutter (Android + desktop macOS untuk dev)
- **DB:** SQLite (`sqflite`)
- **State:** Provider

## Fitur Utama
1. **Login Role**
   - Owner: akses penuh
   - Staff: operasional (Beranda, Stok, Akun)
   - Seed user: admin/1234 (owner), karyawan/0000 (staff)
   - Password disimpan dalam bentuk hash (SHA-256)

2. **Pemasukan (Kasir)**
   - Grid produk → input jumlah → otomatis isi transaksi
   - Validasi stok: tidak bisa jual jika stok kurang
   - Manual input tetap ada
   - Summary card sebelum simpan

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

7. **Manajemen Akun & Audit**
   - Owner dapat kelola staff (CRUD, reset password)
   - User dapat ganti foto profil & password
   - Penghapusan transaksi oleh staff wajib isi alasan (Audit Trail)
   - Owner dapat melihat, restore, atau hapus permanen audit log

## Skema Database (v5)
- **products**: id, name (unique), price, stock
- **transactions**: id, type, amount, category_id, description, date, user_id, product_id, quantity
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

## Catatan UI/UX
- Login: gradient maroon + card modern
- Produk grid diurutkan: stok > 0 di atas, lalu alfabetis
- Owner dashboard: combo card saldo + mini pemasukan/pengeluaran
- Target harian opsional (progress + confetti) di header dashboard

## Build & Icon
- Icon: `assets/icon_toko.png`
- `flutter_launcher_icons` sudah ada di `pubspec.yaml`
- Jalankan manual:
  ```bash
  flutter pub get
  flutter pub run flutter_launcher_icons
  ```

## Reset DB (Hard Reset)
- DB version: 5
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
