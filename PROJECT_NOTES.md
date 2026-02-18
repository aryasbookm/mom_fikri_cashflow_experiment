> **Tentang:** Catatan teknis aktif: status fitur, keputusan desain, dan checklist operasional.
> **Audiens:** Developer, AI agent, reviewer teknis.
> **Konteks:** Dipakai saat pengembangan harian, handoff, dan validasi sebelum merge.

# Project Notes — Toko Kue Mom Fiqry

## Ringkasan
- **Nama aplikasi (label & UI):** Toko Kue Mom Fiqry
- **Tujuan:** Cashflow + stok terintegrasi untuk UMKM toko kue.
- **Platform:** Flutter (Android + desktop macOS untuk dev)
- **DB:** SQLite (`sqflite`)
- **State:** Provider
- **Release Notes:** lihat `CHANGELOG.md` (timeline v0.9.0 → v1.0.0-rc3)

## SOP Kolaborasi AI (Aktif)
- **Role boundary:** Gemini = mentor/reviewer, Codex = eksekutor perubahan repo, User = approver final.
- **Best-practice default:** tidak menunggu keyword; perubahan non-trivial wajib lewat Best-Practice Check singkat.
- **Blocker timebox:** maksimal 3 percobaan atau 45–60 menit, lalu fallback/pivot.
- **Quality gate sebelum merge:** Happy Path + Edge Case + Rollback/Recovery.
- **Dokumentasi:** gunakan prinsip impacted-docs-only.
- **Project capsule:** maintain `WORKFLOW.md` + fixed port + browser profile dedicated untuk isolasi konteks antar proyek.

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
   - Cloud backup (Drive) sudah tersedia untuk Android: upload/restore file `.zip` (hybrid) via Google Drive `appDataFolder` dan kompatibel restore `.db` legacy.
   - Catatan dev: pengujian macOS dapat terkendala keychain/signing environment (Personal Team).
   - Debug owner: tombol simulasi lupa backup (mundurkan timestamp 4 hari).
   - Auto-backup lokal: berjalan saat app paused/tutup sesi, jeda minimum 5 menit, simpan 5 file terakhir di `auto_backups/`.
   - Deteksi perubahan data memakai snapshot jumlah transaksi + produk + audit log.
   - Restore: dua jalur (manual file picker + auto-backup list internal).
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

3.1 **Kelola Kategori (Owner)**
   - Owner dapat mengelola kategori langsung dari tab Akun.
   - Kategori sistem default:
     - IN: `Penjualan Kue`, `Pemasukan Lain`
     - OUT: `Bahan Baku`, `Operasional`, `Gaji`
   - Kategori sistem tidak bisa diubah/hapus.
   - Kategori custom yang sudah pernah dipakai transaksi tidak bisa dihapus.
   - Kategori custom yang belum dipakai bisa diubah/hapus.
   - Tersedia tombol **Tambah Kategori** di layar Kelola Kategori; tipe mengikuti tab aktif (Pemasukan/Pengeluaran).
   - Sinkronisasi startup memastikan kategori sistem wajib tetap tersedia untuk data existing.

4. **Produksi & Stok**
   - Produksi menambah stok
   - Penjualan & waste mengurangi stok
   - Produk baru bisa ditambah (nama + harga)
   - Produk dapat memiliki foto opsional (galeri/kamera) yang disimpan lokal per perangkat
   - Waste dicatat sebagai transaksi `type='WASTE'`
   - Daftar stok mendukung filter tampilan: **Aktif** (default), **Arsip**, **Semua**
   - Seed produk default dalam kondisi **arsip** (`is_active=0`) agar dashboard awal bersih
   - Produk arsip otomatis aktif saat stok ditambah (`stock > 0`)
   - Hapus permanen produk bersifat **guarded**:
     - hanya boleh jika `stock == 0`
     - dan produk belum pernah dipakai di `transaction_items`
     - jika tidak memenuhi syarat, arahkan user ke aksi arsip
   - Smart Reactivation saat tambah produk:
     - jika nama produk sama dengan produk arsip (case-insensitive), user ditawari aktivasi ulang
     - saat aktivasi ulang, harga dan min stok dapat diperbarui mengikuti input baru
     - jika nama sama dan produk sudah aktif, penambahan ditolak untuk mencegah duplikasi

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
   - Backup data ke file `.zip` (berisi database + foto produk) dengan opsi share + simpan ke Download
   - Restore via file picker (Android pakai `FileType.any`) dengan rollback, validasi versi, dan validasi struktur
   - Restore memicu refresh data + reset filter laporan/riwayat
   - Cloud backup Android: upload backup `.zip` (database + foto produk) ke Google Drive `appDataFolder`
   - Cloud backup mode hybrid:
     - default: data-only (tanpa foto) untuk backup rutin,
     - opsi manual: full backup (dengan foto) untuk migrasi perangkat.
   - Auto-Backup Cloud (opsional):
     - toggle manual di menu Akun (default OFF),
     - berjalan maksimal 1x/24 jam,
     - hanya untuk owner yang sudah login Google Drive,
     - hanya mode data-only (`includeImages=false`),
     - hanya jalan jika ada perubahan data sejak backup cloud terakhir.
   - Retensi cloud: simpan maksimal **10** file backup terbaru; file cloud tertua dipruning otomatis setelah upload sukses.
   - Cloud restore Android: pulihkan dari backup cloud terbaru atau file cloud terpilih (via daftar)
   - UI cloud menampilkan metadata lokal: "Terakhir Backup Cloud: [tanggal/jam]"
   - Restore cloud menampilkan bottom sheet daftar backup (nama file, tanggal modifikasi, ukuran)
   - Daftar restore cloud menandai item terbaru dengan badge "Terbaru"
   - Pesan error jaringan cloud dibuat ramah pengguna (tanpa detail exception mentah)
   - Backup cloud sukses ikut memperbarui metadata backup global agar banner pengingat dashboard ikut reset (sinkron lokal + cloud)
   - Aksi akun cloud adaptif:
     - jika belum login, tombol menjadi "Hubungkan Akun Google Drive"
     - jika sudah login, tombol menjadi "Ganti Akun Google Drive" dengan konfirmasi sebelum putus akun lalu pilih akun ulang
   - Kompatibilitas restore: file `.db` lama tetap didukung (database only, tanpa foto produk)

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
- Owner dashboard fresh install: banner backup dan widget/toggle peringatan stok tidak ditampilkan sampai ada data operasional (transaksi/produksi/stok nyata).
- Target harian opsional (progress + confetti) di header dashboard
- Transaksi sekarang menyimpan timestamp lengkap (tanggal + jam)
- Kasir (catatan pemasukan) memakai kartu grid compact vertical stack:
  - thumbnail produk rounded,
  - harga tanpa desimal agar cepat dibaca,
  - ukuran avatar responsif agar kartu terasa lebih terisi.
- Akun: tampilan grouped sections:
  - Backup Lokal
  - Backup Cloud
  - Pengaturan Google Drive
  - Style: ListTile + card sections (lebih rapat & terstruktur)
  - Urutan aksi backup diseragamkan: Auto-Backup -> Cadangkan -> Pulihkan (lokal & cloud).
  - Catatan backup dipindah ke panel foldable "Info & Catatan Penting" agar layar lebih bersih.

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

## Checklist Persiapan Demo Sidang
- [ ] Data sanitization: bersihkan data testing tidak relevan dari database lokal sebelum presentasi.
- [ ] Offline readiness: pastikan aplikasi tetap bisa dibuka dan mencatat transaksi tanpa internet (local DB tetap berfungsi).
- [ ] Cloud demo flow:
  - [ ] Login Google Drive berhasil (akun testing).
  - [ ] Tunjukkan metadata backup cloud terbaru dari UI.
  - [ ] Simulasi restore: data lokal berubah sesuai file cloud yang dipilih.
- [ ] Reporting logic:
  - [ ] Grafik (`fl_chart`) berubah sesuai data transaksi terbaru.
  - [ ] Export PDF berhasil dibuat dan dapat dibuka.
- [ ] Edge case narrative: siapkan jawaban "apa yang terjadi jika proses backup/restore gagal di tengah jalan?" (rollback-safe behavior).
- [ ] Produksi & arsip:
  - [ ] Filter `Aktif/Arsip/Semua` menampilkan daftar sesuai status produk.
  - [ ] Hapus permanen ditolak jika stok masih ada.
  - [ ] Hapus permanen ditolak jika produk memiliki riwayat transaksi.
  - [ ] Produk dengan stok 0 dan tanpa riwayat transaksi bisa dihapus permanen.
- [ ] Konsistensi aset stok:
  - [ ] Pastikan metrik total stok di dashboard menggunakan seluruh produk (bukan hanya filter tampilan produksi).
  - [ ] Verifikasi perubahan filter `Aktif` vs `Semua` di layar produksi tidak mengubah nilai total stok global.

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
