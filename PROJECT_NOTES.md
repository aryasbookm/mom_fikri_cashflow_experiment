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
- **Release channel map:** `main` = stable, `codex/*` = experimental.

## SOP Kolaborasi AI (Aktif)
- **Role boundary:** Gemini = mentor/reviewer, Codex = eksekutor perubahan repo, User = approver final.
- **Best-practice default:** tidak menunggu keyword; perubahan non-trivial wajib lewat Best-Practice Check singkat.
- **Blocker timebox:** maksimal 3 percobaan atau 45–60 menit, lalu fallback/pivot.
- **Quality gate sebelum merge:** Happy Path + Edge Case + Rollback/Recovery.
- **Dokumentasi:** gunakan prinsip impacted-docs-only.
- **Project capsule:** maintain `WORKFLOW.md` + fixed port + browser profile dedicated untuk isolasi konteks antar proyek.

## Rencana Fase 4 (Final)
Prioritas (catatan: fitur arsip kategori membutuhkan migrasi schema DB v9):
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
   - Instalasi baru: **tanpa akun default**; aplikasi langsung masuk onboarding untuk membuat akun owner pertama.
- Password disimpan dalam bentuk hash (SHA-256)
- Quick login sidik jari (opsional):
  - muncul di layar login jika device mendukung biometric dan ada sesi login terakhir.
  - sesi biometric diaktifkan otomatis setelah login manual berhasil.
  - user bisa mematikan lewat tombol `Nonaktifkan Sidik Jari`.
- Tab Akun untuk owner dilindungi PIN (session 5 menit, panjang PIN fleksibel)
   - Dialog PIN menyediakan opsi Logout/Ganti Akun dengan konfirmasi

2. **Pemasukan (Kasir)**
  - Grid produk → tambah ke keranjang (multi-item)
  - Validasi stok per item
  - Manual input tetap ada
  - Ringkasan total otomatis
  - Mendukung prefill dari OCR asistif (draft hasil scan catatan) untuk mempercepat migrasi dari buku.
  - UX viewport diperluas:
    - header produk + pencarian ikut scroll (tidak fixed),
    - footer tanggal/simpan tetap sticky namun lebih ringkas,
    - cart bar auto-hide saat scroll turun dan auto-show saat scroll naik.

3. **Pengeluaran**
   - Input manual
   - Kategori bisa tambah via opsi **Lainnya**

3.1 **Kelola Kategori (Owner)**
   - Owner dapat mengelola kategori langsung dari tab Akun.
   - Kategori sistem default:
     - IN: `Penjualan Kue`, `Pemasukan Lain`, `Saldo Awal`, `Penyesuaian Saldo`
     - OUT: `Bahan Baku`, `Operasional`, `Gaji`, `Penyesuaian Saldo`
   - Kategori sistem tidak bisa diubah/hapus/arsip.
   - Kategori custom bisa diarsipkan (disembunyikan dari input transaksi) dan bisa diaktifkan kembali.
   - Tombol aksi kategori sistem disembunyikan agar tidak menjadi tombol pajangan.
   - Hapus kategori custom memakai smart delete:
     - jika sudah dipakai transaksi -> soft delete (`is_active=0`),
     - jika belum dipakai -> hard delete.
   - Kategori arsip yang sudah dipakai transaksi tidak bisa dihapus permanen.
   - UI menampilkan badge status per item (`Sistem`/`Custom`) serta indikator penggunaan (`Dipakai N transaksi`) untuk mengurangi trial-error.
   - Tampilan default hanya kategori aktif; kategori arsip dapat ditampilkan via toggle `Tampilkan Arsip`.
   - Tambah kategori dengan nama yang sama seperti kategori arsip akan mengaktifkan kembali kategori lama.
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
   - POC Insight AI (online): trigger via ikon `✨` di AppBar kanan atas; mengirim ringkasan 30 hari ke Gemini dan menampilkan 3 saran bisnis dalam dialog.
   - AppBar AI trigger hardened:
     - saat state beranda belum siap (sesaat setelah login), klik awal tidak lagi diam tanpa respons;
     - user menerima snackbar status dan tombol siap dipakai segera setelah state terikat.
  - Entrypoint OCR ditempatkan sebagai aksi sekunder:
    - FAB Beranda dihapus untuk menghindari duplikasi aksi input utama.
    - akses OCR dipindah ke section **Migrasi dari Buku** di layar Riwayat (body) agar kontekstual untuk input historis.
    - ikon scan dipindah dari AppBar agar AppBar tetap fokus ke aksi analisis (AI insight).
  - Riwayat memakai pola scroll penuh:
    - filter, search, migrasi, dan ringkasan tidak lagi mengunci viewport list.
    - area daftar transaksi jadi lebih longgar pada layar HP kecil.
   - Konteks AI 30 hari sekarang mencakup dua sisi:
     - produk terlaris (maks 3 item),
     - produk kurang laris (maks 3 item),
     agar saran tidak hanya fokus pada produk lambat.
   - Prompt AI dioptimalkan ke bahasa UMKM lokal (tanpa istilah korporat), dengan format tetap 3 poin:
     `🌟 Bintang Toko`, `🔍 Evaluasi Produk Kurang Laris`, `💰 Pantau Dompet`.
   - AI rate-limit handling:
     - jika kena `429`, UI membaca jeda dari `Retry-After` (atau fallback 60 detik) lalu menjalankan cooldown.
     - setelah request sukses, cooldown singkat tetap diterapkan untuk mencegah spam klik.
     - selama cooldown tombol AI nonaktif dan menampilkan hitung mundur agar status transparan ke user.
    - parser 429 diperluas untuk membaca detail quota (`QuotaFailure`/`RetryInfo`) sehingga UI bisa membedakan indikasi RPM/TPM/RPD.
    - jika terindikasi RPD (limit harian), tombol AI tidak lagi pakai cooldown 60 detik berulang; user diarahkan untuk coba lagi besok.
   - Arsitektur OCR kini fallback-ready:
    - `AiOcrService` tidak lagi memanggil Gemini secara langsung.
    - Provider OCR dipisah ke kontrak `AiVisionProvider`.
    - Routing dilakukan oleh `AiProviderRouter` dengan urutan provider berbasis `--dart-define=AI_PROVIDER_ORDER=...`.
    - Provider aktif:
      - `GeminiVisionProvider` (utama),
      - `GroqVisionProvider` (fallback).
    - Urutan default fallback: `gemini,groq`.
   - AI Insight juga memakai fallback provider order yang sama (`gemini,groq` by default), jadi saat provider utama limit/sementara gagal, insight tetap mencoba provider berikutnya.
   - Pesan error insight disanitasi agar tidak misleading:
    - bukan lagi default “periksa internet” untuk semua kasus,
    - status API key/akses/model/server dipetakan ke pesan yang relevan.
   - Quota guard OCR diselaraskan dengan fallback:
    - jika lock harian berasal dari provider utama tetapi fallback provider tersedia, OCR tidak di-hard-block oleh guard lokal.
    - ini mencegah kondisi “scan terkunci” padahal provider cadangan sebenarnya masih bisa dipakai.
   - Router OCR kini fallback untuk error lebih luas:
    - bila provider pertama gagal karena format respons/provider mismatch, sistem tetap mencoba provider berikutnya.
   - Error OCR di UI dibuat lebih transparan:
    - user bisa membedakan masalah key/akses/model/server dari masalah “AI merespons tapi format draft transaksi tidak valid”.
   - OCR Human-in-the-Loop v2:
    - transaksi hasil scan mendukung `needs_review` + `warning` untuk kandidat typo/ambigu.
    - UI review menampilkan ringkasan jumlah transaksi dan jumlah item yang perlu review manual.
    - metadata non-transaksi dipisah (`date_detected`, `notes_found`, `ignored_lines`) agar baris seperti tanggal/uang bersih/total tidak otomatis masuk sebagai transaksi barang.
   - Observability OCR provider:
    - error 4xx dari provider sekarang menampilkan sumber provider (`Gemini/Groq`) dan detail body response jika ada, sehingga troubleshooting request/model menjadi lebih presisi.
   - Default OCR Groq model disetel ke `meta-llama/llama-4-scout-17b-16e-instruct` karena model vision Groq lama (`llama-3.2-11b-vision-preview`) sudah decommissioned.
   - Robust parsing:
    - jika provider mengirim JSON terpotong/tidak lengkap, parser OCR tidak lagi melempar `FormatException` mentah ke UI; user menerima pesan retry yang jelas.
   - Kapasitas output OCR:
    - batas output provider dinaikkan ke 2500 token dengan timeout 35 detik untuk menangani halaman buku dengan volume item tinggi (hingga sekitar 30 transaksi) tanpa mudah terpotong.
   - OCR salvage behavior:
    - ketika model mengembalikan `is_transaction=false` namun tetap ada kandidat item+nominal, hasil tidak lagi dibuang.
    - item dipaksa masuk mode review (`needs_review=true`) agar user tetap mendapat draft editable, bukan halaman error kosong.

10. **Chat AI Keuangan (Asisten Mom Fiqry)**
   - Pertanyaan tanggal sensitif (`hari ini`, `kemarin`, `bandingkan`) diproses dengan jalur lokal deterministik dari `daily_summary` agar tidak bergantung interpretasi LLM.
   - Confidence-Safety Layer aktif di jawaban assistant:
     - metadata `confidence_level` (`high|medium|low`) + `confidence_reason` disimpan per message,
     - bubble chat menampilkan indikator dot keyakinan (tap untuk membuka penjelasan level + alasan),
     - jawaban `medium/low` dipaksa memakai framing ketidakpastian (bukan nada absolut).
   - Jika data harian belum lengkap, assistant memberi guidance eksplisit dan tidak memaksakan angka komparatif.
   - Provider priority preference untuk chat:
     - user dapat memilih urutan prioritas (`Otomatis`, `Groq dulu`, `Gemini dulu`) dari UI,
     - preferensi disimpan lokal dan dipakai untuk routing provider berikutnya,
     - fallback antar-provider tetap otomatis saat provider prioritas limit/error.
   - UX chat disederhanakan:
     - aksi copy/edit di bubble menggunakan haptic (tanpa snackbar bawah),
     - `Tanya Lanjutan` tidak auto-fill input; user mengeksekusi eksplisit via chip.
   - Guard reliability:
     - intent capability/help diperketat ke local template untuk mencegah drift respons,
     - blok `Dasar data/Aksi singkat` hanya tampil pada respons analitik,
     - error Gemini chat `404/401/403` diperlakukan sebagai temporary fallback agar tidak berhenti di jalur `via: error`,
     - intent router berjenjang aktif sebagai gatekeeper (`local fast intent -> AI classifier fallback -> clarification/outside-scope`) sebelum jalur LLM,
     - normalisasi intent memakai seed map typo/singkatan/slang ringan, divalidasi dengan golden tests intent 40+ kasus.
   - Fondasi Action Engine (phase-1):
     - pipeline eksekusi kini dipertegas: `fast-lane lokal -> AI action classifier (JSON) -> deterministic action executor -> clarification fallback`.
     - state percakapan lokal dipakai untuk menafsirkan perintah lanjutan (`idle`, `drafting`, `review`), sehingga konteks edit draf lebih konsisten.
     - observability classifier dicatat pada metadata jawaban (`action_intent`, `action_confidence`, `action_reason`, `action_raw_json_valid`) untuk tuning akurasi.
     - parser JSON classifier memakai sanitizer + extractor agar output LLM berformat markdown/teks campuran tidak menyebabkan crash.
   - Cakupan aksi deterministik yang ditambah:
     - query "produk terjual/laku" dari data transaksi harian (SQLite) agar tidak lagi sering jatuh ke klarifikasi generik.
     - edit draf transaksi via chat mendukung ubah nominal, ubah nama/deskripsi, ubah tipe `MASUK/KELUAR`, ubah tanggal, dan hapus item draf.
   - OCR provider-trace visibility:
    - UI scan menampilkan urutan provider yang dicoba pada request aktif (contoh `Gemini -> Groq`) agar verifikasi fallback tidak perlu menebak dari hasil/error saja.
   - Output AI bersifat asistif/read-only (tidak menulis transaksi otomatis).
   - OCR Asistif (MVP):
    - akses dari FAB `Scan Catatan` di Beranda,
     - alur: foto/galeri -> AI ekstrak JSON draft -> user konfirmasi -> prefill form transaksi,
     - fokus 1 transaksi per scan (bukan parsing 1 halaman penuh),
     - tetap Human-in-the-Loop: data tidak disimpan otomatis, user wajib review dan tekan `Simpan`.
     - proteksi UX duplikasi: setelah simpan sukses dari form, draft di layar scan dibersihkan dan muncul konfirmasi sukses.
    - recovery jaringan: jika OCR gagal sementara (mis. `503`), user bisa `Coba Lagi` dengan foto yang sama.
    - pre-check kuota: jika cooldown/limit harian aktif, tombol kamera/galeri dinonaktifkan dan user diberi pesan dini.
    - kartu migrasi di Riwayat menampilkan status kuota AI langsung, sehingga user tahu kondisi AI sebelum masuk ke layar scan.
    - fallback error OCR disederhanakan agar tidak menampilkan teks teknis mentah dari provider AI.
     - guard anti-halusinasi:
       - AI wajib menilai `is_transaction` sebelum ekstraksi final,
       - jika bukan transaksi, proses prefill diblok dan alasan ditampilkan ke user,
       - validasi app-side tetap berjalan untuk mencegah draft nominal/keterangan tidak valid.
   - OCR Multi-Batch (WIP backend):
     - AI OCR service sudah mendukung output daftar transaksi (`transactions[]`),
     - cap item per scan: 30 transaksi,
     - item invalid (nominal <= 0 atau teks tidak jelas) difilter sebelum masuk tahap review UI.
   - OCR Multi-Batch (UI + save):
     - hasil scan ditampilkan sebagai list transaksi (bukan 1 item),
     - checkbox per baris + aksi `Pilih Semua` / `Batal Pilihan`,
     - nominal dan keterangan dapat diedit cepat di list,
     - batch save menyimpan item yang dicentang sekaligus, lalu tampilkan ringkasan berhasil/gagal.

10. **Onboarding & Penyesuaian Saldo**
   - First-install onboarding (2 langkah):
     - buat akun owner (username + PIN),
     - pilih tanggal cut-off dan isi saldo awal kas fisik.
   - Saldo awal dicatat otomatis sebagai transaksi `IN` kategori `Saldo Awal` pada tanggal cut-off.
   - Tombol utama onboarding (`Lanjut` / `Selesaikan Setup`) menggunakan kontras teks putih agar mudah dibaca.
   - Reminder backup diberi grace baseline setelah onboarding selesai agar user baru tidak langsung menerima warning backup pada kunjungan pertama dashboard.
   - Smart reminder backup (tanpa over-engineering):
     - grace period 3 hari pasca onboarding,
     - jika auto-backup lokal/cloud aktif -> warning hanya saat backup stale (>7 hari) dan ada perubahan data,
     - jika auto-backup nonaktif -> warning standar (>3 hari) dan ada perubahan data.
   - Menu owner `Penyesuaian Saldo Kas` tersedia di tab Akun:
     - input kas fisik saat ini + alasan wajib,
     - sistem menghitung selisih terhadap saldo sistem,
     - selisih `+` -> transaksi `IN`, selisih `-` -> transaksi `OUT`,
     - kategori otomatis `Penyesuaian Saldo`.

## Skema Database (v9)
- **products**: id, name (unique), price, stock, min_stock, is_active
- **transactions**: id, type, amount, category_id, description, date, user_id, product_id, quantity
- **transaction_items**: id, transaction_id, product_id, product_name, unit_price, quantity, total
- **production**, **categories** (`is_active` untuk soft archive), **users** (users memiliki `profile_image_path`)
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

## Technical Debt / Pending
- Android release build warning Java obsolete options:
  - Gejala: warning `source value 8` / `target value 8` saat `flutter build apk --release`.
  - Penyebab saat ini: dependency `printing` (`/Users/aryasaputra/.pub-cache/hosted/pub.dev/printing-5.14.2/android/build.gradle`) masih memakai `JavaVersion.VERSION_1_8`.
  - Dampak: non-fatal (build tetap sukses), tetapi menambah noise warning dan berpotensi jadi blocker pada upgrade toolchain mendatang.
  - Rencana perbaikan: upgrade paket `printing` ke versi yang sudah Java 11+ lalu retest alur PDF/export sebelum merge release final.

## Build & Icon
- Icon: `assets/icon_toko.png`
- `flutter_launcher_icons` sudah ada di `pubspec.yaml`
- Versi branch eksperimen aktif saat ini: `1.1.0-dev+101` (lihat `pubspec.yaml`).
- Aturan rilis APK:
  - build untuk user/tester wajib menaikkan `+buildNumber`,
  - nama file APK harus memuat channel + versi (contoh: `momfiqry-exp-v1.1.0-dev+101.apk`).
- Jalankan manual:
  ```bash
  flutter pub get
  flutter pub run flutter_launcher_icons
  ```

## Konfigurasi AI POC
- Fitur Insight AI membutuhkan internet aktif.
- API key tidak disimpan di source code; jalankan app dengan:
  - `--dart-define=GEMINI_API_KEY=<KEY_ANDA>`
- Opsional ganti model:
  - `--dart-define=GEMINI_MODEL=gemini-2.5-flash`
- Debug verifikasi respons (opsional):
  - `--dart-define=AI_DEBUG_LOG=true` untuk mencetak prompt AI dan raw response Gemini ke terminal.
- Verifikasi UI:
  - Dialog Insight AI menampilkan ringkasan data 30 hari yang dikirim ke AI (pemasukan, pengeluaran, selisih, produk kurang laris) agar user bisa memastikan input AI benar.
  - Jika output AI belum lengkap (belum memuat poin `1)`, `2)`, `3)`), service akan retry 1x dengan prompt lebih ketat.
  - Jika retry AI masih tidak lengkap, service fallback ke 3 saran lokal berbasis data agar dialog tidak kosong/terpotong.

## Reset DB (Hard Reset)
- DB version: 9
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
