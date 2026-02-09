# SPESIFIKASI PROYEK: TOKO KUE MOM FIQRY

## 1. Identitas Aplikasi
- **Nama:** Toko Kue Mom Fiqry (Eksperimen)
- **Tujuan:** Digitalisasi pencatatan keuangan & stok toko kue (menggantikan buku manual).
- **Platform:** Android (Mobile) + pengembangan di desktop.
- **Sifat:** Offline-First (data disimpan lokal di perangkat).

## 2. Tech Stack (Wajib)
- **Framework:** Flutter (Dart).
- **Database:** SQLite (package `sqflite`).
- **State Management:** Provider.
- **UI Style:** Material Design 3, tema marun/krem (bakery).
- **Export PDF:** `pdf` + `printing`.
- **Gamifikasi:** `shared_preferences`, `percent_indicator`, `confetti`.
- **Struk Digital:** `screenshot` + `share_plus` + `path_provider`.
- **Export Itemized:** Excel/PDF menampilkan rincian item per transaksi.

## 3. Aktor & Hak Akses
**Owner (Pemilik):**
- Bisa login.
- Bisa input transaksi (pemasukan/pengeluaran).
- Bisa input produksi & mengelola stok.
- Bisa melihat laporan (grafik) dan riwayat transaksi.
- Bisa hapus transaksi.
- Bisa kelola akun staff (tambah/ubah/hapus, reset password).
- Bisa melihat Audit Log, restore, dan hapus permanen log.

**Staff (Karyawan):**
- Bisa login.
- Bisa input transaksi & produksi untuk operasional.
- Bisa melihat beranda & stok, **tidak** bisa melihat laporan keuangan.
- Bisa menghapus transaksi miliknya dengan alasan (Audit Trail).

## 4. Struktur Database (Tabel)
1. **users:** id, username, pin (hash), role, profile_image_path.
2. **categories:** id, name, type (IN/OUT). Mendukung tambahan kategori via opsi “Lainnya”.
3. **products:** id, name, price, stock.
4. **transactions:** id, type (IN/OUT/WASTE), amount, category_id, description, date, user_id, product_id, quantity.
5. **transaction_items:** id, transaction_id, product_id, product_name, unit_price, quantity, total.
6. **production:** id, product_name, quantity, date, user_id.
7. **deleted_transactions:** audit log penghapusan (original_id, type, amount, category_id, category, description, date, user_id, product_id, quantity, deleted_at, deleted_by, reason).

## 5. Modul Utama
- **Kasir (Pemasukan):** grid produk + input jumlah, validasi stok, ringkasan sebelum simpan.
- **Pengeluaran:** input manual, kategori dinamis.
- **Produksi & Stok:** produksi menambah stok, penjualan & waste mengurangi stok.
- **Waste (Barang rusak/basi):** dicatat sebagai transaksi `WASTE` (amount 0).
- **Laporan:** grafik tren 7 hari, pie chart pemasukan/pengeluaran, toggle tipe, navigasi bulan, export PDF (keuangan + waste).
- **Struk Digital:** detail transaksi + bagikan struk (gambar) dari transaksi pemasukan.
- **Target Harian (Owner):** opsional, progress bar omzet harian + confetti saat tercapai.
- **Riwayat:** filter waktu (hari ini/kemarin/7 hari/bulan ini/semua), summary masuk/keluar/saldo, hapus transaksi, export Excel.
- **Audit Log:** melihat transaksi yang dihapus, restore, hapus permanen.

## 6. Alur Utama
- Buka aplikasi → Login → cek role.
- Owner: Dashboard dengan saldo, stok tersedia, ringkasan hari ini, tombol aksi (pemasukan/pengeluaran/riwayat).
- Staff: Beranda (transaksi hari ini + total setoran), tab Stok, tab Akun.

## 7. Data Awal (Seeding)
- User default: admin/1234 (owner), karyawan/0000 (staff).
- Kategori awal: Penjualan Kue (IN), Bahan Baku/Operasional/Gaji (OUT).
- Produk awal: daftar kue dan snack sesuai data seed (dengan harga, stok awal 0).
