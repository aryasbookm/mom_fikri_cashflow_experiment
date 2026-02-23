> **Tentang:** Riwayat perubahan versi dan fitur proyek secara kronologis.
> **Audiens:** Developer, penguji, reviewer rilis.
> **Konteks:** Dipakai untuk tracking evolusi fitur, regression check, dan bukti progres skripsi.

# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - Phase 4
*Fokus: Pencarian Global, Reminder Backup, Insight Produk Lambat*

### Added
- OCR Asistif MVP (Human-in-the-Loop):
  - menu `Scan Catatan` (ikon scanner di AppBar Beranda owner),
  - ambil foto dari kamera / pilih dari galeri,
  - kirim gambar ke Gemini Vision untuk ekstraksi 1 transaksi menjadi JSON draft (`type`, `amount`, `description`, `category_hint`, `date_iso`, `confidence`, `raw_text`),
  - tampilkan hasil konfirmasi scan sebelum dipakai,
  - lanjutkan ke form `Catat Pemasukan/Pengeluaran` dalam mode prefill (user tetap review dan menekan `Simpan` manual).
  - setelah transaksi OCR berhasil disimpan, layar scan menampilkan snackbar sukses dan membersihkan draft agar tidak mudah terjadi submit ganda.
  - saat scan gagal (contoh `503`), layar scan menyediakan tombol `Coba Lagi` untuk memproses ulang foto terakhir tanpa ambil foto ulang.
  - guard non-transaksi ditambahkan:
    - AI sekarang mengembalikan `is_transaction` + `reason`,
    - foto yang bukan transaksi ditolak sebelum prefill form,
    - validasi lokal diperketat (`amount > 0`, `description/raw_text` cukup jelas) untuk menekan false positive.
- OCR Multi-Batch (backend checkpoint):
  - service OCR kini mengembalikan batch transaksi (`transactions[]`) alih-alih object tunggal.
  - batas maksimum transaksi per scan ditetapkan **30 item** (`maxItemsPerScan=30`) sesuai konteks buku lapangan.
  - filter server-side: item nominal `<= 0` dan item teks tidak jelas otomatis dibuang sebelum diteruskan ke UI.
- OCR Multi-Batch (UI + save flow):
  - panel konfirmasi tunggal diganti menjadi daftar review transaksi hasil scan.
  - setiap baris punya checkbox, pilihan default dicentang, plus aksi cepat `Pilih Semua` / `Batal Pilihan`.
  - nominal/deskripsi bisa diedit langsung di list sebelum simpan.
  - tombol simpan kini dinamis `Simpan N Transaksi`.
  - batch save menyimpan seluruh item tercentang ke SQLite dengan ringkasan hasil `berhasil/gagal`.
- AppBar AI trigger:
  - perbaikan race condition saat pertama login: tombol `Minta Saran AI` kini tidak lagi silent-fail pada klik awal.
  - jika state dashboard belum siap, user mendapat snackbar feedback (`Beranda belum siap...`) alih-alih tidak ada respons.
- Dashboard input entrypoint:
  - ikon `Scan` di AppBar Beranda dipindah agar area analisis lebih bersih.
  - ditambahkan FAB `Tambah Data` di Beranda dengan bottom sheet 3 opsi:
    `Catat Pemasukan`, `Catat Pengeluaran`, `Scan Catatan (AI)`.
- AI quota error handling:
  - parser error `429` kini membaca detail `QuotaFailure`/`RetryInfo` dari response Gemini untuk membedakan indikasi RPM/TPM/RPD.
  - pesan user dibuat lebih spesifik (request per menit, token per menit, atau limit harian).
  - jika terindikasi limit harian (RPD), dashboard tidak lagi memaksa cooldown 60 detik; status dikunci dengan pesan `coba lagi besok`.
- First-install onboarding wajib (owner account + cut-off date + saldo awal kas), aktif otomatis saat tabel user masih kosong.
- Owner-only menu **Penyesuaian Saldo Kas** di tab Akun: input kas fisik + alasan, hitung selisih otomatis, simpan transaksi `IN/OUT` kategori `Penyesuaian Saldo`.
- POC **Insight AI (Owner Dashboard)**:
  - tombol `Minta Saran AI (Online)` untuk menghasilkan 3 saran bisnis berbasis data 30 hari (pemasukan, pengeluaran, produk kurang laris),
  - hasil ditampilkan sebagai dialog teks (read-only, tidak mengubah data transaksi),
  - integrasi via Gemini REST menggunakan `--dart-define=GEMINI_API_KEY=...`.
- Global Search: search bar di Kasir, Stok, dan Riwayat dengan filtering real-time.
- Deep Search Riwayat: pencarian juga mencakup nama produk dari transaksi multi-item.
- Foto produk opsional berbasis filesystem lokal (`product_images/prod_{id}.jpg`) dengan picker galeri/kamera.
- Smart Backup Reminder + catatan rencana auto-backup lokal (toggle + retention) dan cloud backup fase berikutnya.
- Debug owner: tombol simulasi lupa backup (mundurkan timestamp 4 hari).
- Slow Moving Analytics: tampilkan 3–5 produk dengan penjualan terendah (30 hari terakhir) untuk insight operasional.
- Auto-backup lokal: otomatis saat app paused dengan throttle 5 menit + guard perubahan data, simpan 5 file terakhir.
- Restore dua jalur: file manual (file picker) dan auto-backup list internal.
- Cloud Backup Android: upload backup `.zip` ke Google Drive `appDataFolder`.
- Cloud Restore Android: pulihkan database dari backup cloud terbaru (`appDataFolder`).
- Cloud Restore Picker Android: restore dari file cloud terpilih (bukan hanya latest) via bottom sheet list.
- Cloud Metadata UI: tampilkan "Terakhir Backup Cloud" berdasarkan timestamp lokal backup cloud terakhir.
- Backup format v2: paket `.zip` berisi database + folder `product_images` + metadata manifest.
- Hybrid backup mode (manual): pilih **Data Only** (DB saja) atau **Full** (DB + foto produk), dengan flag `includeImages` di `manifest.json`.
- Auto-Backup Cloud (opsional): owner-only, default OFF, data-only, maksimal 1x/24 jam, dan hanya saat ada perubahan data.
- Akun: section backup kini konsisten menjadi **Backup Lokal / Backup Cloud / Pengaturan Google Drive**.
- Produksi: filter daftar stok **Aktif / Arsip / Semua** (default: Aktif).
- Guarded delete produk: hapus permanen hanya diizinkan jika stok `0` dan belum punya riwayat di `transaction_items`.
- Owner: menu **Kelola Kategori** di tab Akun untuk ubah nama kategori custom dan hapus kategori yang belum pernah dipakai transaksi.
- Pemasukan manual: kategori pemasukan kini memprioritaskan non-`Penjualan Kue` (default ke `Pemasukan Lain` bila tersedia) dan menampilkan info bahwa input manual tidak memengaruhi stok produk.
- Export laporan diselaraskan:
  - Excel memakai header yang lebih jelas (`Kategori Transaksi`, `Ringkasan Produk`, `Catatan`, `Detail Produk`) dengan detail item tetap lengkap.
  - PDF menampilkan ringkasan produk untuk transaksi pemasukan (hybrid) dan tetap menyertakan detail item agar lebih mudah dibaca owner.

### Changed
- AI Insight POC:
  - dialog hasil kini menampilkan ringkasan data 30 hari yang benar-benar dikirim ke AI (untuk verifikasi input).
  - jika respons AI terlalu generik/tidak lengkap (belum memuat poin 1/2/3), sistem melakukan 1x retry dengan prompt lebih ketat.
  - batas output token AI dinaikkan agar risiko output terpotong berkurang.
  - jika setelah retry respons masih tidak lengkap, sistem memakai fallback saran lokal (3 poin) agar user tetap mendapat output yang dapat dipakai.
- AI Insight POC:
  - status `429` kini ditangani khusus dengan membaca header `Retry-After` (fallback 60 detik) dan menampilkan pesan tunggu yang jelas ke pengguna.
  - tombol `Minta Saran AI` otomatis cooldown: nonaktif saat loading, nonaktif beberapa detik setelah sukses (anti-spam), dan nonaktif sesuai `Retry-After` saat rate-limit.
  - ditambahkan hitung mundur di dashboard (`AI sedang istirahat...`) agar pengguna tahu kapan bisa mencoba lagi.
- AI Insight POC:
  - konteks AI diperkaya: kini mengirim data `Produk Terlaris (30 Hari)` selain `Produk Kurang Laris (30 Hari)` agar saran lebih seimbang.
  - prompt AI dirombak ke gaya bahasa UMKM lokal (lebih sederhana, menghindari istilah korporat), dengan format output ketat:
    `🌟 Bintang Toko`, `🔍 Evaluasi Produk Kurang Laris`, `💰 Pantau Dompet`.
  - fallback lokal ikut disesuaikan agar output tetap mudah dipahami ketika respons AI tidak memenuhi format.
  - dialog verifikasi "Data terkirim" sekarang menampilkan produk terlaris dan kurang laris sekaligus.
- UI AI Dashboard:
  - kartu besar `Minta Saran AI (Online)` dihapus agar tidak mendominasi beranda.
  - trigger AI dipindah menjadi ikon kecil `✨` di AppBar kanan atas (fitur sekunder, lebih ringan visual).
  - saat cooldown, tekan ikon akan menampilkan snackbar sisa waktu tunggu.
- AI Insight POC: parser response Gemini diperbaiki agar menggabungkan semua `parts.text` (tidak hanya part pertama), sehingga output 3 poin saran tampil utuh.
- AI Insight POC: ditambahkan debug logging opsional (`--dart-define=AI_DEBUG_LOG=true`) untuk menampilkan prompt terkirim dan raw response ke terminal saat verifikasi.
- Smart backup reminder (versi terkontrol):
  - menerapkan grace period 3 hari setelah onboarding selesai.
  - jika auto-backup lokal/cloud aktif, reminder hanya muncul saat backup sangat usang (>7 hari) dan ada perubahan data.
  - jika auto-backup nonaktif, reminder tetap memakai aturan standar (>3 hari) dan ada perubahan data.
- Onboarding first-install:
  - warna teks tombol `Lanjut` / `Selesaikan Setup` diperjelas (kontras putih pada tombol utama).
  - setelah setup selesai, baseline metadata backup diinisialisasi agar banner reminder backup tidak langsung muncul di detik pertama penggunaan.
- Versioning branch eksperimen dinaikkan ke `1.1.0-dev+101` untuk membedakan kanal build dari rilis stable.
- Seed install baru tidak lagi membuat akun default (`admin/1234`, `karyawan/0000`); akun owner dibuat lewat onboarding pertama.
- Kategori sistem diperluas:
  - `Saldo Awal` (IN)
  - `Penyesuaian Saldo` (IN/OUT)
  - tetap terkunci dari ubah/hapus/arsip.
- Branding aplikasi disederhanakan dari "Toko Kue Mom Fiqry (Eksperimen)" menjadi "Toko Kue Mom Fiqry" pada Android/iOS/Web/Desktop.
- Folder kerja proyek diganti dari `mom_fikri_cashflow_experiment` menjadi `mom_fiqry_cashflow_experiment`.
- Dashboard owner: ringkasan harian statis, analitik produk foldable default terbuka.
- Dashboard owner empty-state: banner backup dan kartu/toggle peringatan stok disembunyikan saat aplikasi masih fresh install (belum ada data operasional).
- Cloud backup sukses kini ikut memperbarui metadata backup global, sehingga pengingat backup dashboard sinkron untuk backup lokal maupun cloud.
- Riwayat: result counter dan subtitle match saat pencarian aktif.
- Smart Backup: reminder dan auto-backup hanya berjalan jika ada perubahan data sejak backup terakhir.
- Menu debug Akun: tombol cloud sekarang melakukan backup/restore Google Drive (Android).
- Validasi fitur cloud dilakukan di Android; kendala keychain/signing macOS dicatat sebagai batasan environment development.
- UX cloud: pesan error jaringan dibuat lebih ramah pengguna (tanpa detail exception teknis).
- Kasir (pemasukan): kartu grid produk kini memakai vertical stack responsif dengan thumbnail rounded agar hierarki visual lebih rapat.
- Kasir (pemasukan): fine-tuning visual akhir pada kartu grid:
  - format harga tanpa desimal (contoh `Rp 15.000`),
  - avatar produk diperbesar proporsional (`(tileWidth * 0.15).clamp(28, 52)`),
  - penekanan harga ditingkatkan (font lebih menonjol).
- Restore cloud: daftar backup menandai item terbaru dengan badge "Terbaru".
- Cloud account: aksi akun cloud kini adaptif:
  - saat belum login tampil "Hubungkan Akun Google Drive",
  - saat sudah login tampil "Ganti Akun Google Drive" dengan dialog konfirmasi sebelum disconnect dan re-login.
- UI backup menampilkan catatan kompatibilitas restore (`.zip` termasuk foto, `.db` lama tanpa foto).
- Backup lokal/cloud kini menggunakan file `.zip` agar foto produk ikut tersimpan.
- Restore kini kompatibel dua format:
  - `.zip` memulihkan database + foto produk,
  - `.db` lama tetap didukung (database only, tanpa foto).
- Operasional repo: ditambahkan `WORKFLOW.md` + konvensi `.env` `PORT=3010` untuk fixed-port workflow dan recovery cepat.
- Restore hybrid mode:
  - jika backup `includeImages=true`, restore mengganti database + folder foto produk,
  - jika backup `includeImages=false`, restore hanya mengganti database dan mempertahankan foto lokal.
- Seed produk awal kini default **arsip** (`is_active=0`) dengan `min_stock=5`; produk arsip auto-aktif saat stok bertambah.
- UI Akun backup:
  - urutan item lokal/cloud diseragamkan menjadi **Auto-Backup -> Cadangkan -> Pulihkan**,
  - catatan backup panjang dibuat foldable lewat panel **Info & Catatan Penting** (default tertutup).
- Kasir (catat pemasukan): saat produk yang sama dipilih ulang, input jumlah kini memperbarui qty item di cart (replace), bukan menambah qty lama.
- Produksi (edit produk): ditambahkan field **Penyesuaian Stok (opsional)** pada dialog edit untuk tambah/kurangi stok langsung via nilai `+/-` dengan validasi agar stok tidak minus.
- Dashboard staff: FAB `+` di beranda dihapus dan diganti dua aksi langsung (**Catat Pemasukan** dan **Catat Pengeluaran**) agar konsisten dengan alur owner.
- Proteksi kategori:
  - kategori sistem (`Penjualan Kue`, `Pemasukan Lain`, `Bahan Baku`, `Operasional`, `Gaji`) tidak bisa diubah/hapus.
  - kategori yang sudah dipakai transaksi tidak bisa dihapus permanen.
- Seed & sinkronisasi kategori:
  - seed install baru diselaraskan dengan kategori sistem (termasuk `Pemasukan Lain` dan `Gaji`).
  - data existing dibackfill otomatis agar kategori sistem yang wajib selalu tersedia.
- Kelola Kategori:
  - ditambahkan aksi **Tambah Kategori** langsung di layar Kelola Kategori (owner).
  - status item diperjelas (badge **Sistem/Custom** + info **Dipakai N transaksi**).
  - UI disederhanakan menjadi satu daftar aktif + toggle **Tampilkan Arsip** di AppBar.
  - tombol aksi untuk kategori sistem disembunyikan (tanpa tombol pajangan).
  - `Hapus` menjadi smart action:
    - kategori custom terpakai -> soft delete (`is_active=0`, disembunyikan dari input baru),
    - kategori custom belum terpakai -> hard delete,
    - kategori arsip terpakai -> hard delete ditolak.
  - tambah kategori dengan nama yang sama seperti kategori arsip akan mengaktifkan kembali kategori lama (tanpa duplikasi).
  - dropdown input transaksi kini hanya menampilkan kategori aktif.
- Safe-area Android:
  - layar `Catat Pemasukan/Pengeluaran` dan `Detail Transaksi` kini menambahkan inset bawah sistem agar tombol aksi tidak tertutup navigation bar 3 tombol.
- Database:
  - skema dinaikkan ke **v9** dengan kolom `categories.is_active` (default aktif) untuk mendukung arsip kategori secara aman pada data existing.

---

## [v1.0.0-rc3] - 2026-02-10 (Experimental #3)
*Fokus: Keamanan Data & Penyempurnaan UX*

### Added
- Sistem Backup & Restore robust (rollback + validasi versi + validasi struktur).
- Restore epoch untuk reset state otomatis setelah restore.
- PIN guard tab Akun (session 5 menit, PIN fleksibel).
- Opsi Logout/Ganti Akun dari dialog PIN (dengan konfirmasi).
- Top Produk (7 hari) di dashboard owner.

### Changed
- UI menu Akun dirombak menjadi grouped sections terstruktur.
- Android file picker untuk restore memakai `FileType.any` + validasi manual `.db`.

### Fixed
- Deadlock akses saat staff perlu logout dari akun owner yang terkunci PIN.

---

## [v1.0.0-rc2] - 2026-02-10 (Experimental #2)
*Fokus: Smart Inventory & Optimalisasi Transaksi*

### Added
- Multi-item transaction (keranjang belanja) + tabel `transaction_items`.
- Export Excel & PDF itemized (rincian item per transaksi).
- Target harian opsional (progress + confetti).
- Smart inventory control: `min_stock`, `is_active`, bulk aktif/arsip, low-stock alert toggle, auto-activate saat stok masuk.
- Dropdown alasan pengurangan stok + catatan opsional.
- Timestamp transaksi penuh (tanggal + jam).

### Changed
- Kasir hanya menampilkan produk aktif dengan stok > 0.
- Laporan PDF menampilkan jam transaksi.

### Fixed
- Perbaikan format tanggal/jam pada export agar konsisten.

---

## [v1.0.0-rc1] - 2026-02-10 (Experimental #1)
*Fokus: Audit Trail & Manajemen Akun*

### Added
- Manajemen akun: CRUD staff, reset password, ganti password & foto profil.
- Audit trail penghapusan transaksi (alasan wajib), audit log owner, restore, hapus permanen.
- Export Excel dari Riwayat (sesuai filter aktif) dengan format rupiah + tabel.
- Laporan: tren 7 hari, pie chart pemasukan/pengeluaran, export PDF keuangan + waste.
- Struk digital: detail item transaksi + share struk gambar.
- Backup & restore DB dengan validasi versi/struktur + rollback (baseline fitur).

### Changed
- Penyimpanan password user menjadi hash (SHA-256).
- Transaksi menyimpan timestamp lengkap (tanggal + jam).
- UI Akun ditata ulang jadi grouped sections.

### Fixed
- Refresh audit log agar item langsung hilang setelah restore/delete.
- Isolasi transaksi staff (hindari data admin muncul di akun staff).
- Error akses foto profil di macOS dengan menyalin file ke app storage.

### Security
- Audit trail persisten di SQLite untuk semua penghapusan transaksi staff.
- Owner-only audit log dengan restore/hapus permanen.
- PIN guard untuk akses tab Akun owner.

---

## [v0.9.0] - 2026-02-10 (Base Version / Cashflow Utama)
*Fokus: Core POS & Manajemen Stok Dasar*

### Added
- Sistem stok terintegrasi: produksi menambah stok, penjualan & waste mengurangi stok.
- Produk baru bisa ditambahkan (nama + harga).
- Grid kasir dengan validasi stok + ringkasan transaksi sebelum simpan.
- Laporan keuangan dengan toggle pemasukan/pengeluaran dan navigasi bulan.
- Riwayat transaksi dengan filter waktu + ringkasan (masuk/keluar/saldo).
- Log barang rusak/basi harian di halaman produksi.
- Dashboard owner dengan ringkasan harian dan total stok tersedia.

### Changed
- Dashboard owner menggunakan kartu keuangan gabungan (saldo + pemasukan/pengeluaran).
- Staff dashboard ditata ulang: tab Beranda, Stok, Akun.
- Produk di grid kasir diurutkan stok > 0 di atas, lalu alfabetis.
- Produksi menampilkan stok produk dan daftar produksi harian (accordion).

### Fixed
- Validasi penjualan agar stok tidak bisa minus.
- Undo transaksi pemasukan mengembalikan stok.
- Transaksi `WASTE` tidak ikut perhitungan kas harian/riwayat kas.

### Security
- Staff tidak dapat melihat laporan keuangan (owner-only).
