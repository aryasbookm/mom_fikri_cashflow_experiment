# UAT Backup & Restore

## Quality Gate Checklist
- [ ] Happy Path tervalidasi.
- [ ] Minimal 1 Edge Case tervalidasi.
- [ ] Rollback/Recovery tervalidasi.

| Scenario | Steps | Expected Result |
| --- | --- | --- |
| 1. Backup berhasil | 1. Buka aplikasi, login sebagai owner. 2. Buka tab Akun. 3. Tekan "Backup Data". 4. Pastikan share sheet muncul. 5. Pastikan file backup tersimpan di folder Download (atau lokasi fallback). | Share sheet muncul. File backup berekstensi `.db` tersimpan dengan timestamp. |
| 2. Restore berhasil | 1. Pastikan ada file backup `.db` yang valid. 2. Buka tab Akun. 3. Tekan "Restore Data". 4. Konfirmasi dialog. 5. Pilih file backup yang valid. 6. Tunggu proses selesai. | SnackBar sukses muncul. Data transaksi/produk/kategori berubah sesuai file backup. Jika belum berubah, restart aplikasi lalu cek ulang. |
| 3. Restore gagal + rollback | 1. Siapkan file `.db` yang valid tetapi bukan database Mom Fiqri (mis. `testing.db` dengan tabel dummy). 2. Buka tab Akun. 3. Tekan "Restore Data". 4. Pilih file `.db` tersebut. | Muncul pesan: "Struktur database tidak dikenali. Data lama dikembalikan." Data lama tetap aman (rollback). |
| 4. Schema version check | 1. Siapkan file backup `.db` dengan schema version lebih tinggi dari aplikasi. 2. Buka tab Akun. 3. Tekan "Restore Data". 4. Pilih file backup tersebut. | Muncul pesan: "Versi backup terlalu baru untuk aplikasi ini." Data lama tetap aman (rollback). |
| 5. Restore saat di laporan | 1. Buka tab Laporan. 2. Ubah bulan/filter pada layar laporan. 3. Pindah ke tab Akun, jalankan restore berhasil. 4. Kembali ke tab Laporan. | Filter laporan kembali ke default (bulan sekarang dan tampilan awal), data tampil sesuai backup baru. |
