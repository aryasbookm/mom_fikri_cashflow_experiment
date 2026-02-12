> **Tentang:** Rangkuman teknis siap pakai untuk Bab 3/4 skripsi (arsitektur, keputusan, milestone).
> **Audiens:** Penulis skripsi, dosen penguji, reviewer akademik.
> **Konteks:** Dipakai saat penyusunan naskah, persiapan sidang, dan jawaban teknis saat demo.

# THESIS_REFERENCE — Toko Kue Mom Fiqry

## 1. Posisi Proyek (untuk Bab 1/3)
- **Judul sistem:** Aplikasi kasir dan manajemen stok UMKM berbasis Flutter (offline-first).
- **Tujuan utama:**
  - pencatatan pemasukan/pengeluaran,
  - kontrol stok produksi,
  - backup/restore lokal dan cloud,
  - dukungan audit operasional.
- **Konteks penggunaan:** toko kue skala UMKM dengan konektivitas internet yang tidak selalu stabil.

## 2. Stack dan Arsitektur (untuk Bab 3)
- **Framework utama:** Flutter.
- **Bahasa utama logika bisnis:** Dart.
- **Database lokal:** SQLite (`sqflite`).
- **State management:** Provider.
- **Arsitektur aplikasi:**
  - `lib/screens/` = presentasi/UI,
  - `lib/providers/` = state + business rules,
  - `lib/services/` = layanan teknis (backup/cloud/export/image),
  - `lib/database/` = skema, seed, migrasi,
  - `lib/models/` = model data.

Catatan untuk sidang:
- Persentase bahasa lain di GitHub (C/C++/Swift/CMake/Ruby) berasal dari file platform build bawaan Flutter (`android/`, `ios/`, `macos/`, `linux/`, `windows/`), bukan inti logika bisnis.

## 3. Keputusan Teknis Penting (Design Decisions)

### 3.1 Produk dan stok
- Produk memiliki status `is_active` (arsip/aktif) untuk soft-delete.
- Seed produk default disimpan sebagai arsip agar dashboard awal tidak noisy.
- Produk arsip bisa aktif otomatis saat stok ditambah (`stock > 0`).
- **Guarded hard delete:** produk hanya bisa dihapus permanen jika:
  1. stok `0`,
  2. tidak pernah direferensikan di `transaction_items`.

### 3.2 Foto produk
- Foto disimpan lokal per perangkat (`product_images/prod_{id}.jpg`).
- Kompresi diterapkan saat input (quality + resize) untuk menekan ukuran backup.
- UI fallback tetap aman jika file foto tidak ditemukan.

### 3.3 Backup & restore (hybrid)
- Backup manual mendukung dua mode:
  - **Data-only** (DB saja),
  - **Full** (DB + foto produk).
- Manifest backup menyimpan metadata mode (`includeImages`).
- Restore bersifat rollback-safe (gagal restore => rollback ke data sebelumnya).
- Restore data-only mempertahankan foto lokal (trade-off: ada potensi mismatch foto pada restore lintas-device).

### 3.4 Cloud backup
- Cloud backup default mode **data-only** untuk efisiensi kuota.
- Cloud full backup tetap tersedia sebagai opsi manual.
- Retensi cloud dibatasi **10 file terbaru** dengan auto-prune file terlama.
- Auto-cloud backup bersifat opsional (toggle), owner-only, dan berjalan maksimal 1x/24 jam dengan guard perubahan data.

### 3.5 Auto-backup lokal
- Trigger event-based saat aplikasi masuk state `paused`.
- Throttle lokal: jeda minimum **5 menit** + guard perubahan data.
- Retensi lokal: 5 file auto-backup terbaru.

## 4. Fitur Inti yang Sudah Tersedia (untuk Bab 4)
- Login role owner/staff + proteksi PIN owner di area akun.
- Kasir pemasukan:
  - pemilihan multi-produk,
  - validasi stok,
  - keranjang foldable + sticky summary.
- Pengeluaran dengan kategori dinamis.
- Produksi & waste stok.
- Riwayat transaksi + export.
- Laporan ringkas owner.
- Backup/restore lokal + cloud.
- Pengelolaan akun Google Drive.

## 5. Validasi Pengujian (Quality Gate ringkas)
Gunakan pola evaluasi:
1. **Happy path** (alur normal berhasil end-to-end),
2. **Edge case** (input/keadaan tidak normal),
3. **Recovery** (rollback/restore saat gagal).

Contoh skenario yang relevan:
- Restore backup invalid => data lama tetap aman.
- Hapus produk bertransaksi => ditolak dan diarahkan ke arsip.
- Backup cloud ke-11 => backup terlama terprune otomatis.
- Auto-backup lokal tidak spam (throttle 5 menit efektif).

## 6. Milestone Commit Utama (bahan narasi progres)
- `e980e82` — zip backup + image restore support.
- `90adcbc` — hybrid backup mode (data-only vs full).
- `a52609b` — stabilisasi restore image.
- `70a90f6` — guarded product delete + stock list filters.
- `6d6b36b` — smart reactivation produk arsip saat nama duplikat.
- `8b515c4` — foldable sticky cart pada alur pemasukan.
- `bb1ba46` — cloud retention + hybrid cloud selector.
- `9467ff6` — auto cloud backup opsional (data-only).
- `cfdcfd5` — throttle auto-backup lokal 5 menit.

## 7. Batasan Sistem Saat Ini (untuk diskusi ilmiah)
- Data-only restore lintas-device dapat menyebabkan mismatch foto lokal (karena foto tidak disinkronkan).
- Auto-cloud backup belum memiliki mode Wi-Fi only.
- Pengujian release lintas perangkat masih perlu diperluas untuk simulasi jaringan buruk.

## 8. Kalimat Ringkas Siap Pakai (untuk naskah skripsi)
"Sistem dikembangkan secara iteratif dengan Flutter (Dart) dan SQLite menggunakan arsitektur berbasis Provider. Mekanisme backup menerapkan strategi hybrid (data-only dan full) dengan perlindungan rollback-safe serta retensi otomatis pada penyimpanan cloud, sehingga menyeimbangkan aspek keamanan data, efisiensi sumber daya, dan kemudahan operasional UMKM."
