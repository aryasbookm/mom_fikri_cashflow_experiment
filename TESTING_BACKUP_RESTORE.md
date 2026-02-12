# UAT Backup & Restore

## Quality Gate Checklist
- [ ] Happy Path tervalidasi.
- [ ] Minimal 1 Edge Case tervalidasi.
- [ ] Rollback/Recovery tervalidasi.

| Scenario | Steps | Expected Result |
| --- | --- | --- |
| 1. Backup manual data-only berhasil | 1. Login owner. 2. Buka Akun -> Backup Data. 3. Pilih mode Data Saja (tanpa foto). 4. Simpan/share file backup. | Backup `.zip` berhasil dibuat. Ukuran file relatif kecil. |
| 2. Backup manual full berhasil | 1. Login owner. 2. Buka Akun -> Backup Data. 3. Aktifkan Sertakan Foto Produk. 4. Simpan/share file backup. | Backup `.zip` berhasil dibuat. Ukuran file lebih besar dibanding data-only. |
| 3. Restore full `.zip` berhasil | 1. Siapkan backup `.zip` full valid. 2. Buka Akun -> Restore Data. 3. Pilih file backup. | Data transaksi/produk pulih dan foto produk ikut pulih. |
| 4. Restore data-only menjaga foto lokal | 1. Siapkan backup `.zip` data-only valid. 2. Pastikan device saat ini sudah punya foto produk lokal. 3. Jalankan restore. | DB ter-restore, foto lokal tetap dipertahankan (tidak dihapus). |
| 5. Restore legacy `.db` kompatibel | 1. Siapkan file backup `.db` lama valid. 2. Jalankan restore dari Akun. | Restore sukses untuk data DB. Foto produk tidak dipulihkan dari file `.db` legacy. |
| 6. Restore gagal + rollback | 1. Siapkan file backup invalid (bukan backup app / zip rusak). 2. Jalankan restore. | Restore ditolak. Muncul pesan gagal + rollback, data lama tetap aman. |
| 7. Restore saat di laporan | 1. Buka layar Laporan dan ubah filter bulan/range. 2. Jalankan restore berhasil dari Akun. 3. Kembali ke Laporan. | Filter laporan kembali ke default dan data tampil sesuai hasil restore terbaru. |
| 8. Auto-backup lokal throttle 5 menit | 1. Pastikan Auto-backup Lokal ON. 2. Lakukan perubahan data. 3. Pause app (home) lalu cek backup. 4. Ulang pause lagi dalam <5 menit. 5. Ulang setelah >5 menit dengan perubahan data baru. | Backup baru tidak spam pada interval <5 menit. Backup baru muncul lagi setelah >5 menit dan ada perubahan data. |
| 9. Cloud retention 10 file | 1. Login Google Drive. 2. Lakukan backup cloud >10 kali. 3. Buka daftar backup cloud. | Jumlah backup cloud maksimal 10 file; file tertua otomatis terhapus (prune). |
