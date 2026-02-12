# Panduan User 1 Halaman — Toko Kue Mom Fiqry

## Tujuan
Panduan cepat untuk operasional harian: jualan, stok, dan keamanan data.

## 1) Login & Hak Akses
- **Owner**: akses penuh (kasir, produksi, laporan, akun, backup/restore).
- **Staff**: akses operasional (kasir, produksi, akun terbatas).
- Masuk dengan username + PIN yang diberikan.

## 2) Alur Harian (Disarankan)
1. Buka aplikasi dan login.
2. Catat penjualan di **Catat Pemasukan** (pilih produk atau input manual).
3. Jika produksi baru masuk, update di menu **Produksi**.
4. Cek **Peringatan Stok** di dashboard owner.
5. Tutup aplikasi normal (auto-backup lokal aktif jika toggle ON).

## 3) Cara Catat Penjualan (Kasir)
1. Buka **Catat Pemasukan**.
2. Pilih produk dari grid (tap kartu produk untuk tambah ke keranjang).
3. Buka ringkasan keranjang (bar bawah) jika ingin cek detail item.
4. Pilih tanggal bila perlu.
5. Tekan **Simpan**.

Catatan:
- Jika stok tidak cukup, transaksi akan ditolak otomatis.
- Produk tanpa foto tetap tampil dengan placeholder huruf awal.

## 4) Cara Kelola Stok
- Masuk ke **Produksi** untuk tambah stok.
- Gunakan filter **Aktif / Arsip / Semua** untuk melihat produk.
- Produk arsip dapat aktif lagi saat stok ditambah.
- Hapus permanen hanya bisa jika:
  - stok = 0, dan
  - belum pernah dipakai transaksi.

## 5) Backup & Restore (Wajib Paham)
### Backup Lokal
- Menu: **Akun > Backup Data**.
- Pilihan mode:
  - **Data Saja**: kecil/cepat.
  - **Lengkap + Foto**: lebih besar, untuk pindah perangkat.

### Backup Cloud (Google Drive)
- Hubungkan akun Google dulu.
- Menu: **Akun > Backup ke Google Drive**.
- Auto-backup cloud bisa diaktifkan (harian, data-only).

### Restore Data
- Menu: **Akun > Restore Data** (lokal) atau **Restore dari Google Drive**.
- File `.zip` (hybrid) memulihkan data + (opsional) foto.
- File `.db` lama tetap didukung (data saja).

## 6) Kapan Pakai Data Saja vs Lengkap
- **Data Saja**: backup rutin harian.
- **Lengkap + Foto**: sebelum ganti HP / migrasi perangkat.

## 7) Troubleshooting Singkat
- **“Restore gagal”**: coba file backup lain yang lebih baru/valid.
- **Foto produk tidak muncul setelah restore data-only lintas device**:
  - lakukan restore dari backup **Lengkap + Foto**.
- **Cloud gagal**: cek internet + login Google Drive.

## 8) Kebiasaan Aman (Checklist)
- [ ] Auto-backup lokal ON.
- [ ] Auto-backup cloud ON (owner, jika internet tersedia).
- [ ] Lakukan backup **Lengkap + Foto** minimal sebelum pindah perangkat.
- [ ] Cek tanggal backup terakhir di menu Akun.
