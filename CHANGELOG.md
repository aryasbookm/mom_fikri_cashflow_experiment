> **Tentang:** Riwayat perubahan versi dan fitur proyek secara kronologis.
> **Audiens:** Developer, penguji, reviewer rilis.
> **Konteks:** Dipakai untuk tracking evolusi fitur, regression check, dan bukti progres skripsi.

# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - Phase 4
*Fokus: Pencarian Global, Reminder Backup, Insight Produk Lambat*

### Added
- Fondasi arsitektur OCR multi-provider (fallback-ready):
  - `AiVisionProvider` interface sebagai kontrak provider Vision OCR.
  - `GeminiVisionProvider` untuk isolasi implementasi Gemini dari layer UI/service utama.
  - `AiProviderRouter` untuk routing provider berurutan (berdasarkan `AI_PROVIDER_ORDER`, default `gemini`) dan auto-fallback saat provider utama terkena limit sementara (`429`) atau error temporary.
  - `AiOcrService` kini memanggil router (bukan hardcoded Gemini), sehingga siap ditambah provider kedua tanpa ubah UI.
- Provider fallback kedua ditambahkan:
  - `GroqVisionProvider` (`https://api.groq.com/openai/v1/chat/completions`) dengan model default `llama-3.2-11b-vision-preview`.
  - konfigurasi key via `--dart-define=GROQ_API_KEY=...`.
  - urutan provider default router diperbarui menjadi `gemini,groq`.
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
- Layar **Chat AI Keuangan** (`AiChatbotScreen`) ditambahkan dan terhubung dari tombol `Tanya Lanjutan` pada dialog Insight.
- Polishing UI chatbot:
  - quick question chips (1-tap),
  - copy jawaban AI ke clipboard,
  - aksi clear chat dari AppBar.
- Konteks chatbot diperluas dengan `product_catalog` (stok semua produk) agar jawaban produk tidak hanya bertumpu pada sampel top/slow.
- Riwayat chatbot kini disimpan lokal (dengan guard hash snapshot data) agar sesi bisa dilanjutkan jika user kembali ke layar chat pada konteks data yang sama.
- Chatbot kini mendukung memory lokal ringan (opt-in) untuk personalisasi:
  - menyimpan `preferred_name`, `preferred_salutation`, `tone` via `SharedPreferences`,
  - command lokal didukung: lihat memori, ubah nama/sapaan, ubah tone, dan lupakan memori,
  - update nama berbeda memerlukan konfirmasi (`ya` / `tidak`) sebelum overwrite.
- Chatbot kini mendukung `chat_action_intent` untuk import draf transaksi via chat:
  - perintah seperti "tambahkan transaksi..." diparse ke JSON draft ketat (`import_transactions_draft`),
  - hasil valid otomatis diarahkan ke layar review OCR yang sama (human-in-the-loop, tidak auto-save),
  - draf dibatasi maksimal 30 item dan item ambigu ditandai `needs_review`.
  - Phase 1 inferensi tanggal: item mendukung metadata `date_source` (`explicit|inferred|unknown`) dan aturan deterministik `inferred => needs_review=true`.
  - layar review menampilkan banner peringatan saat data terdeteksi parsial/inferensi (`is_partial_day`, `missing_opening_block`, `missing_closing_total`, `inference_notes`).
  - Phase 2 smart parser: nominal gabungan seperti `10.000 + 5.000` dihitung deterministik oleh parser lokal, deskripsi dibersihkan dari ekor nominal, dan baris non-transaksi (`Total/Uang Bersih/Saldo`) difilter ke `ignored_lines`.
  - Phase 3 audit & anti-duplication:
    - hash import chat (`import_hash`) dibawa dari service ke layar review,
    - sebelum simpan, sistem mendeteksi hash yang sama pada riwayat lokal (72 jam) dan meminta konfirmasi ulang jika terduplikasi,
    - transaksi dari jalur chat import diberi tag audit sumber di deskripsi (`[chat_import:<hash8>]`),
    - audit ringkas penyimpanan chat import dicatat lokal untuk tracking hash/jumlah/nominal.
  - Phase 4 automated tests:
    - unit test `chat_import_draft_model_test.dart` menutup rule inferensi tanggal deterministik, smart math parser, dan filter baris non-transaksi.
    - unit test `chat_import_audit_service_test.dart` menutup deteksi duplikasi hash dalam window dan validasi abaikan record di luar window.
- OCR parity Phase 1:
  - `OcrTransactionDraft` kini mendukung `date_source` formal (`explicit|inferred|unknown`) dengan rule deterministik `inferred => needs_review=true`.
  - prompt OCR Gemini/Groq diperketat agar mengisi `date_source` dan mewajibkan review saat tanggal hasil inferensi.
  - layar review OCR kini menggunakan `date_source` asli dari hasil OCR (bukan fallback turunan `date_iso`).
  - unit test baru `ocr_transaction_draft_model_test.dart` ditambahkan untuk validasi normalisasi `date_source` + deterministic review.
- OCR parity Phase 2:
  - `OcrPostProcessor` kini menerapkan parser nominal gabungan deterministik dari teks OCR (`10.000 + 5.000` => `15000`) dengan warning lokal saat nominal diubah parser.
  - deskripsi transaksi OCR kini dibersihkan dari ekor token nominal agar hasil review lebih rapi.
  - filter baris ringkasan/non-transaksi tetap dipertahankan (`Total/Uang Bersih/Saldo`) ke `notes_found` dan `ignored_lines`.
  - unit test baru `ocr_post_processing_test.dart` ditambahkan untuk validasi smart math parser + data filtering OCR.
- OCR parity Phase 3 (audit trail & dedup):
  - jalur OCR kamera kini memiliki audit hash lokal (`ocr_scan_hash`) berbasis isi gambar (`sha256`) untuk deteksi duplikasi dalam window 72 jam.
  - sebelum simpan, jika hash OCR sama ditemukan pada riwayat lokal, app menampilkan dialog konfirmasi simpan ulang.
  - transaksi dari jalur OCR kamera kini ditandai audit sumber di deskripsi (`[ocr_scan:<hash8>]`).
  - audit ringkas penyimpanan OCR kamera dicatat lokal (hash/jumlah/nominal) via `OcrImportAuditService`.
  - unit test baru `ocr_import_audit_service_test.dart` ditambahkan untuk validasi dedup window OCR.
- OCR parity Phase 4 (reliability & edge-case testing):
  - perluasan test parser OCR untuk skenario nominal berantai (`10.000 + 5.000 + 2.000`) agar perhitungan deterministik tetap konsisten.
  - penambahan test OCR untuk item tanggal inferensi/parsial agar aturan review wajib tetap terjaga pada payload edge case.
  - penambahan test batas `maxItems` untuk memastikan payload OCR besar tetap dipotong aman sesuai limit.
  - penambahan test dedup OCR untuk kasus hash tidak cocok (dalam window) agar tidak terjadi false-positive duplicate.
- Undo quick-win (OCR + chat import save flow):
  - setelah simpan dari layar OCR assist, aplikasi menampilkan `SnackBar` dengan aksi `Urungkan` selama 12 detik.
  - aksi `Urungkan` melakukan rollback transaksi yang baru dibuat (soft-delete via audit log), berlaku untuk jalur OCR kamera dan chat import.
  - `TransactionProvider.addTransaction` kini mengembalikan `id` transaksi baru agar rollback dapat menargetkan transaksi yang tepat.
- Payload AI kini menyertakan agregat kategori 30 hari (pemasukan/pengeluaran) untuk Insight dan Chatbot agar jawaban lebih spesifik.
- Fondasi service chatbot finansial ditambahkan (`AiChatbotService`):
  - bounded context (hanya jawab konteks keuangan toko),
  - history window terbatas (maks 8 pesan),
  - cache fingerprint + fallback provider `AI_CHAT_PROVIDER_ORDER` (default `groq,gemini`),
  - retry adaptif (backoff + jitter + hormati `Retry-After` saat 429).
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
- AI Insight kini ikut memakai strategi multi-provider fallback (urutan `AI_PROVIDER_ORDER`, default `gemini,groq`) sehingga jika provider pertama kena rate limit/temporary error, sistem otomatis mencoba provider berikutnya.
- Seleksi provider AI kini aware konfigurasi key:
  - provider tanpa API key tidak lagi ikut antrean fallback (OCR & Insight),
  - mencegah error fallback (`GROQ_API_KEY belum diset`) menutupi akar masalah provider utama.
- OCR kini mendukung model-chain Gemini untuk fallback intra-provider:
  - satu request OCR akan mencoba model sesuai urutan `GEMINI_OCR_MODEL_CHAIN` (default: `gemini-2.5-flash -> gemini-3-flash -> gemini-2.5-flash-lite`) sebelum pindah ke provider berikutnya.
  - membantu memanfaatkan kuota harian per-model secara lebih optimal pada mode free-tier.
- AI Insight dioptimalkan untuk efisiensi kuota:
  - hasil insight dicache 45 menit berbasis fingerprint data (income/expense/net + top/slow product), sehingga klik berulang dengan data sama tidak memanggil API lagi.
  - payload produk dinormalisasi (maks 3 item/top dan 3 item/slow) untuk menekan token.
  - prompt diringkas agar lebih padat (tanpa basa-basi) namun format tetap ketat.
  - batas output insight dinaikkan dari 420 ke 900 untuk mengurangi respons terpotong.
- AI Insight v2 diperbarui:
  - prompt kini mewajibkan output JSON terstruktur (`temuan`, `alasan_berbasis_data`, `aksi_nyata`, `prioritas`) agar parsing konsisten,
  - ada parser + validasi schema lokal sebelum dirender ke teks,
  - fallback prompt ketat jika respons awal tidak valid.
- Cooldown Insight tidak lagi hardcoded:
  - UI dashboard kini memakai cooldown yang disarankan service (cache lebih singkat, provider call lebih adaptif),
  - retry provider internal memakai exponential backoff + jitter untuk error sementara.
- Routing AI Insight dipisahkan dari OCR:
  - order provider insight kini dikontrol `AI_INSIGHT_PROVIDER_ORDER` (default `groq,gemini`) agar insight cenderung memakai model teks dulu.
  - model Gemini untuk insight dipisah melalui `GEMINI_INSIGHT_MODEL`, tidak lagi otomatis mengikuti model OCR.
- Chatbot finansial diperketat untuk kualitas jawaban berbasis data:
  - prompt kini mewajibkan output JSON terstruktur (`status`, `jawaban`, `dasar_data`, `aksi_singkat`, `data_tambahan_dibutuhkan`),
  - validasi lokal menolak respons ambigu/tidak grounded (terutama saat user menanyakan kategori spesifik),
  - retry prompt ketat dijalankan jika format/grounding gagal, lalu fallback deterministik lokal dipakai jika tetap tidak valid.
- Guard mutlak Insight ditambahkan:
  - jalur Insight kini memblokir model Gemini Vision (`flash`/`pro`) untuk mencegah kebocoran kuota OCR.
  - fallback Gemini untuk Insight diwajibkan memakai model Gemma (default `gemma-3-12b`).
- Error Insight AI diperjelas:
  - pesan fallback tidak lagi selalu menyalahkan internet,
  - status HTTP umum (`400/401/403/404/5xx`) dipetakan ke pesan yang lebih akurat untuk user.
- AI quota guard disesuaikan untuk mode multi-provider:
  - lock harian dari provider utama tidak lagi memblokir OCR/scan jika fallback provider sudah terkonfigurasi,
  - mengurangi kasus false lock saat kuota provider utama habis tetapi provider cadangan masih tersedia.
- OCR fallback behavior diperkuat:
  - router OCR sekarang lanjut coba provider berikutnya untuk kegagalan non-rate-limit (mis. format respons/provider mismatch), bukan berhenti di provider pertama.
- OCR error copy diperjelas:
  - status HTTP umum OCR (`401/403/404/5xx`) dipetakan ke pesan yang lebih spesifik,
  - kegagalan format respons (AI membalas tetapi bukan JSON transaksi valid) ditampilkan sebagai pesan yang jelas, tidak lagi generik.
- OCR Human-in-the-Loop ditingkatkan:
  - transaksi kini mendukung flag `needs_review` + `warning` untuk baris yang diduga typo/ragu baca.
  - hasil scan menampilkan ringkasan `X transaksi, Y perlu review`.
  - metadata non-transaksi dipisah dari transaksi (`date_detected`, `notes_found`, `ignored_lines`) agar catatan seperti tanggal/total/uang bersih tidak mencemari draft transaksi.
  - baris `needs_review` diberi penanda visual (warna kuning + warning) agar user mengedit manual sebelum simpan.
- Interactive Date Grouping Lite pada review OCR:
  - daftar transaksi kini dikelompokkan visual per tanggal (`dateIso`) agar item lintas-hari lebih mudah ditinjau.
  - tersedia aksi `Tanggal Baru dari Sini` untuk menyisipkan grup tanggal baru dan menerapkan tanggal ke seluruh item di bawahnya.
  - setiap baris transaksi punya kontrol edit tanggal individual + terapkan ke bawah.
  - item tanpa tanggal ditandai sebagai `perlu review` sebelum simpan.
- Review OCR kini menampilkan ringkasan total:
  - total nominal otomatis dihitung dari item yang dipilih user.
  - validasi ditampilkan per kelompok tanggal (bukan global) agar aman untuk foto dengan multi-tanggal.
  - total kumulatif per tanggal dihitung dari `(total tersimpan di DB) + (total scan grup)`.
  - jika ditemukan pembanding total dari catatan dan mapping tanggalnya jelas, aplikasi menampilkan status cocok/selisih.
  - jika pembanding tidak jelas, status ditandai `belum bisa divalidasi` (tanpa warning palsu).
- Review OCR kini menerapkan smart default IN/OUT:
  - setelah hasil scan masuk, tipe transaksi diset mengikuti suara mayoritas (`IN` atau `OUT`) dalam satu halaman.
  - jika pola data terlihat dominan nama produk, default cenderung `IN` (pemasukan) sebagai heuristik aman.
  - user tetap bisa mengubah tipe per transaksi secara manual sebelum simpan.
  - ditambahkan aksi batch `Semua IN` dan `Semua OUT` untuk override cepat seluruh item review.
- Learning Dictionary OCR (v1):
  - aplikasi merekam koreksi deskripsi manual user saat simpan transaksi scan.
  - koreksi tersebut dipakai sebagai auto-correct pada scan berikutnya untuk mengurangi typo berulang.
  - penyimpanan kamus menggunakan local preferences agar ringan dan tidak mengubah skema database.
  - kamus melakukan preload awal dari daftar produk di database agar OCR langsung lebih familiar dengan nama produk toko.
- OCR provider error observability ditingkatkan:
  - pesan 4xx OCR kini menyertakan label provider (`[Gemini]` / `[Groq]`) dan detail message dari body response jika tersedia,
  - mempermudah identifikasi akar masalah nyata (model/key/request schema) dibanding pesan generik.
- Default model OCR Groq diperbarui dari model vision lama yang sudah deprecated ke `meta-llama/llama-4-scout-17b-16e-instruct`.
- Parsing OCR JSON diperkeras untuk kasus respons terpotong:
  - `FormatException` dari JSON decode kini ditangkap dan diubah ke pesan user-friendly (`respons OCR terpotong/tidak lengkap`) agar tidak tampil raw error parser.
- Kapasitas output OCR dinaikkan:
  - `maxOutputTokens` (Gemini) dan `max_tokens` (Groq) dinaikkan dari 420 ke 2500.
  - timeout request OCR dinaikkan dari 25 detik ke 35 detik untuk mengurangi respons terpotong pada halaman catatan panjang (target hingga ~30 transaksi).
- OCR salvage mode:
  - jika provider menandai `is_transaction=false` tetapi tetap mengembalikan kandidat transaksi, aplikasi tidak lagi gagal total.
  - kandidat tetap ditampilkan sebagai draft dengan `needs_review=true` + warning, agar user bisa edit manual.
- OCR post-processing deterministik ditambahkan setelah respons AI:
  - nominal gabungan seperti `20.000 + 20.000` otomatis dijumlahkan menjadi `40000` sebelum ditampilkan/simpan.
  - baris ringkasan non-transaksi (`Total`, `Jumlah`, `Uang Bersih`, `Saldo Akhir`, dll.) otomatis dipindah ke `notes_found/ignored_lines`, tidak dimasukkan sebagai transaksi.
  - teks ambigu/typo pendek dipaksa `needs_review=true` agar benar-benar muncul sebagai item review manual (lampu kuning).
- Prompt OCR Gemini/Groq dipertegas dengan konteks domain **toko kue Mom Fiqry Cake** + aturan tegas pemisahan transaksi vs catatan ringkasan.
- OCR provider trail:
  - layar scan kini menampilkan jejak provider yang dicoba per request (mis. `Gemini -> Groq`) untuk transparansi fallback saat testing/demo.
- UX `Catat Pemasukan/Pengeluaran` dirapikan:
  - padding atas diperkecil agar tidak ada ruang kosong berlebih di awal layar.
  - area produk diubah ke `CustomScrollView` (sliver) sehingga header `Pilih Produk / Input Manual / Cari produk` ikut scroll saat list digulir.
  - footer aksi (`Tanggal` + `Simpan`) tetap sticky di bawah namun dibuat lebih compact.
  - ringkasan keranjang (`cart bar`) otomatis disembunyikan saat scroll turun dan muncul lagi saat scroll naik agar viewport produk lebih luas.
- Riwayat UX dirapikan:
  - header filter/search/migrasi/ringkasan kini ikut scroll bersama daftar transaksi (tidak lagi menahan area konten terlalu besar).
  - section `Migrasi dari Buku` dibuat lebih compact agar tidak mendominasi layar.
  - section migrasi menampilkan status AI langsung (`AI siap dipakai` / pesan limit) sebelum user menekan scan.
- Riwayat kini mendukung filter tanggal kustom:
  - mode `Tanggal` untuk melihat transaksi pada satu hari tertentu.
  - mode `Rentang` untuk melihat transaksi dari tanggal awal sampai akhir pilihan user.
  - hasil filter kustom tetap terintegrasi dengan pencarian transaksi yang sudah ada.
  - tampilan filter disederhanakan ke chips utama (`Hari Ini`, `7 Hari`, `Bulan Ini`, `Semua`) + menu `Filter Lanjutan`.
  - label chip diperjelas menjadi `7 Hari Terakhir` agar selaras dengan logika rolling window.
  - menu `Filter Lanjutan` menampung `Tanggal`, `Rentang`, dan `Pilih Bulan` cepat.
  - `Pilih Bulan` kini memakai month-year picker langsung (tanpa memilih tanggal sembarang di bulan tersebut).
- Dashboard input entrypoint disederhanakan:
  - FAB Beranda dihapus agar tidak menduplikasi aksi utama `Catat Pemasukan/Pengeluaran`.
  - entry OCR dipindah ke section khusus **Migrasi dari Buku** di layar Riwayat (body, bukan AppBar) agar konteks lebih tepat.
- OCR Asistif kini melakukan pre-check status kuota sebelum proses scan:
  - tombol `Ambil Foto` / `Pilih Galeri` otomatis nonaktif saat cooldown/limit harian AI aktif,
  - pengguna mendapat peringatan dini di layar (tanpa harus ambil foto dulu baru gagal),
  - status blokir kuota disinkronkan dari trigger AI Dashboard dan OCR agar perilaku konsisten.
- Error handling AI/OCR diperhalus:
  - fallback error yang bersifat teknis/mentah tidak lagi ditampilkan ke user.
  - pesan di UI disederhanakan menjadi kalimat ringkas dan actionable.
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
