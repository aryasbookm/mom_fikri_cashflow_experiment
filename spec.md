# SPESIFIKASI PROYEK: TOKO KUE MOM FIQRY

## 1. Identitas Aplikasi
- **Nama:** Toko Kue Mom Fiqry
- **Tujuan:** Digitalisasi pencatatan keuangan & stok toko kue (menggantikan buku manual).
- **Platform:** Android (Mobile) + pengembangan di desktop.
- **Sifat:** Offline-First (data disimpan lokal di perangkat).

## 2. Tech Stack (Wajib)
- **Framework:** Flutter (Dart).
- **Database:** SQLite (package `sqflite`).
- **State Management:** Provider.
- **UI Style:** Material Design 3, tema marun/krem (bakery).

## 3. Aktor & Hak Akses
**Owner (Pemilik):**
- Bisa login.
- Bisa input transaksi (pemasukan/pengeluaran).
- Bisa input produksi & mengelola stok.
- Bisa melihat laporan (grafik) dan riwayat transaksi.
- Bisa hapus transaksi.

**Staff (Karyawan):**
- Bisa login.
- Bisa input transaksi & produksi untuk operasional.
- Bisa melihat beranda & stok, **tidak** bisa melihat laporan keuangan.
- Bisa hapus transaksi yang diinput hari itu.

## 4. Struktur Database (Tabel)
1. **users:** id, username, pin, role.
2. **categories:** id, name, type (IN/OUT). Mendukung tambahan kategori via opsi “Lainnya”.
3. **products:** id, name, price, stock.
4. **transactions:** id, type (IN/OUT/WASTE), amount, category_id, description, date, user_id, product_id, quantity.
5. **production:** id, product_name, quantity, date, user_id.

## 5. Modul Utama
- **Kasir (Pemasukan):** grid produk + input jumlah, validasi stok, ringkasan sebelum simpan.
- **Pengeluaran:** input manual, kategori dinamis.
- **Produksi & Stok:** produksi menambah stok, penjualan & waste mengurangi stok.
- **Waste (Barang rusak/basi):** dicatat sebagai transaksi `WASTE` (amount 0).
- **Laporan:** pie chart pemasukan/pengeluaran, toggle tipe, navigasi bulan.
- **Riwayat:** filter waktu (hari ini/kemarin/7 hari/bulan ini/semua), summary masuk/keluar/saldo, hapus transaksi.

## 6. Alur Utama
- Buka aplikasi → Login → cek role.
- Owner: Dashboard dengan saldo, stok tersedia, ringkasan hari ini, tombol aksi (pemasukan/pengeluaran/riwayat).
- Staff: Beranda (transaksi hari ini + total setoran), tab Stok, tab Akun.

## 7. Data Awal (Seeding)
- User default: admin/1234 (owner), karyawan/0000 (staff).
- Kategori awal: Penjualan Kue (IN), Bahan Baku/Operasional/Gaji (OUT).
- Produk awal: daftar kue dan snack sesuai data seed (dengan harga, stok awal 0).
