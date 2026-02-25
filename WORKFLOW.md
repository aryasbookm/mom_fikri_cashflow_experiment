# WORKFLOW.md

## 1) Project Identity
- Project: `mom_fiqry_cashflow_experiment`
- Repo Path: `/Users/aryasaputra/Projects/mom_fiqry_cashflow_experiment`
- Branch Utama: `main`
- Branch Kerja: `codex/*`

## 2) Runtime & Ports
- App URL (Web): `http://localhost:3010`
- Fixed Port Policy: `3010` (jangan dipakai proyek lain)
- Auth Redirect (dev): `http://localhost:3010/...`

## 3) Browser Profile
- Browser Profile Name: `Profile-MomFiqry`
- Catatan: gunakan profile ini khusus project ini untuk menghindari bentrok cookie/auth.

## 4) Terminal Sessions
- Dev Server Tab: `mom-fiqry-dev`
- Git Tab: `mom-fiqry-git`
- Opsional Test Tab: `mom-fiqry-test`

## 5) Start / Stop Commands
- Install deps: `flutter pub get`
- Run dev (web fixed port): `flutter run -d chrome --web-port 3010`
- Run test: `flutter test`
- Stop dev: `Ctrl + C` di tab `mom-fiqry-dev`

## 6) Env & Secrets
- Env file: `.env`
- Variabel wajib:
  - `PORT=3010`
- Catatan: Flutter web tetap memakai `--web-port` saat run, variabel `PORT` dipakai sebagai konvensi runbook lintas proyek.
- Variabel opsional (AI POC, jangan commit key):
  - jalankan dengan `--dart-define=GEMINI_API_KEY=...`
  - provider fallback (opsional):
    - `--dart-define=GROQ_API_KEY=...`
    - OCR route: `--dart-define=AI_PROVIDER_ORDER=gemini,groq`
    - Insight route: `--dart-define=AI_INSIGHT_PROVIDER_ORDER=groq,gemini`
    - Chat route: `--dart-define=AI_CHAT_PROVIDER_ORDER=groq,gemini`
  - opsional model OCR:
    - primary tunggal: `--dart-define=GEMINI_MODEL=gemini-3-flash`
    - chain OCR Gemini: `--dart-define=GEMINI_OCR_MODEL_CHAIN=gemini-3-flash,gemini-2.5-flash,gemini-2.5-flash-lite`
  - opsional model Insight/Chat:
    - `--dart-define=GEMINI_INSIGHT_MODEL=gemma-3-12b`
    - `--dart-define=GEMINI_CHAT_MODEL=gemma-3-12b`
    - `--dart-define=GROQ_CHAT_MODEL=llama-3.1-8b-instant`
    - guard insight memblokir model Gemini Vision (`flash`/`pro`) agar kuota OCR tidak bocor.
  - opsional model fallback:
    - `--dart-define=GROQ_VISION_MODEL=meta-llama/llama-4-scout-17b-16e-instruct`

## 6.1) AI Build Profiles (Gunakan Konsisten)
- `ocr_gemini_only`
  - `--dart-define=GEMINI_API_KEY=...`
  - `--dart-define=AI_PROVIDER_ORDER=gemini`
  - `--dart-define=GEMINI_OCR_MODEL_CHAIN=gemini-3-flash,gemini-2.5-flash,gemini-2.5-flash-lite`
- `ocr_chain_with_groq`
  - profile `ocr_gemini_only` + `--dart-define=GROQ_API_KEY=...`
  - `--dart-define=AI_PROVIDER_ORDER=gemini,groq`
- `insight_text_only`
  - `--dart-define=GROQ_API_KEY=...`
  - `--dart-define=AI_INSIGHT_PROVIDER_ORDER=groq`
  - opsional fallback Gemini text-only: `--dart-define=AI_INSIGHT_PROVIDER_ORDER=groq,gemini --dart-define=GEMINI_INSIGHT_MODEL=gemma-3-12b`
- `chat_text_only`
  - `--dart-define=GROQ_API_KEY=...`
  - `--dart-define=AI_CHAT_PROVIDER_ORDER=groq`
  - opsional fallback Gemini text-only: `--dart-define=AI_CHAT_PROVIDER_ORDER=groq,gemini --dart-define=GEMINI_CHAT_MODEL=gemma-3-12b`

## 6.2) AI Preflight Check (Wajib Sebelum Build/Test)
- [ ] Key untuk provider aktif sudah di-pass via `--dart-define`.
- [ ] Route OCR/Insight sesuai target test (`AI_PROVIDER_ORDER` vs `AI_INSIGHT_PROVIDER_ORDER`).
- [ ] Route chat sesuai target test (`AI_CHAT_PROVIDER_ORDER`).
- [ ] Model OCR chain dan model Insight/Chat tidak tertukar (vision vs text-only).
- [ ] Jika tujuan hanya uji UI, gunakan mock/fixture lokal dulu (hindari burn kuota API).

## 7) Quick Verification
- [ ] Server jalan di `3010`.
- [ ] Login/auth tidak bentrok dengan proyek lain.
- [ ] Alur inti aplikasi bisa dibuka normal.
- [ ] Tidak ada konflik session/cookie antar proyek.

## 8) Recovery (30 detik)
1. Buka tab terminal `mom-fiqry-dev`.
2. Jalankan `flutter run -d chrome --web-port 3010`.
3. Buka browser profile `Profile-MomFiqry`.
4. Akses `http://localhost:3010`.

## 9) Release & Build SOP
- Sebelum build APK yang akan dibagikan ke user/tester:
  - naikkan `version:` di `pubspec.yaml` (minimal `+buildNumber` wajib naik).
- Format kanal rilis:
  - `stable` untuk jalur operasional toko (`main`),
  - `experimental` untuk jalur uji fitur (`codex/*`).
- Penamaan file APK setelah build (rename manual):
  - `momfiqry-stable-v<versionName+build>.apk`
  - `momfiqry-exp-v<versionName+build>.apk`
- Contoh:
  - `momfiqry-stable-v1.0.1+2.apk`
  - `momfiqry-exp-v1.1.0-dev+101.apk`
- Catatan:
  - Android menolak update jika `versionCode` tidak lebih tinggi dari APK terpasang.
  - Jika build eksperimen dipasang di device operasional, pastikan tahu risikonya karena package sama (tidak bisa side-by-side tanpa ubah identitas aplikasi).

## 10) Final APK Test Checklist (Wajib Sebelum Share)
- [ ] `pubspec.yaml` sudah naik `versionName+buildNumber` dibanding APK terakhir.
- [ ] Jalankan build sesuai channel:
  - `stable` dari branch `main`
  - `experimental` dari branch `codex/*`
- [ ] Verifikasi login owner/staff berhasil.
- [ ] Verifikasi alur inti transaksi:
  - tambah pemasukan/pengeluaran sukses
  - histori dan saldo berubah sesuai nominal
- [ ] Verifikasi backup-restore dasar (local/cloud sesuai target test) dan app tetap bisa dibuka setelah restore.
- [ ] Verifikasi export (Excel/PDF) bisa dibuat tanpa crash.
- [ ] Verifikasi AI preflight (key + provider order + model route) sesuai profil build.
- [ ] Rename artefak APK dengan format kanal:
  - `momfiqry-stable-v<versionName+build>.apk`
  - `momfiqry-exp-v<versionName+build>.apk`

## 11) Chatbot Quality Checklist (Data Real)
- [ ] Uji 5 pertanyaan kategori spesifik (contoh: bahan baku/operasional) dan pastikan jawaban menyebut kategori yang ditanya.
- [ ] Uji 3 pertanyaan di luar konteks finansial; respons harus kalimat guardrail standar.
- [ ] Uji 3 pertanyaan saat data kategori minim; respons harus menyebut `data tambahan dibutuhkan`.
- [ ] Uji konsistensi dasar data:
  - nominal ringkasan 30 hari di jawaban harus konsisten dengan dashboard
  - tidak boleh menukar `stock_now` dengan `total_qty`
- [ ] Uji retry format:
  - paksa prompt ambigu 2x
  - pastikan app tetap mengembalikan jawaban terstruktur (fallback lokal jika perlu).
- [ ] Uji memory lokal chatbot:
  - set nama/sapaan eksplisit, lalu tanyakan finansial dan pastikan sapaan dipakai natural (maks 1x)
  - minta "apa yang kamu ingat tentang saya" untuk verifikasi data tersimpan
  - ganti nama berbeda dan pastikan bot meminta konfirmasi overwrite
  - minta "lupakan saya" dan pastikan memori terhapus.
- [ ] Uji chat action import transaksi:
  - kirim perintah "tambahkan transaksi..." berisi daftar item, pastikan app membuka layar review OCR (bukan auto-save)
  - pastikan item ambigu ditandai `needs_review`
  - pastikan item dengan `date_source=inferred` otomatis `needs_review=true`
  - pastikan banner parsial/inferensi tampil jika `is_partial_day` / `missing_*` / `inference_notes` terisi
  - uji nominal gabungan (`10.000 + 5.000`) dan pastikan parser lokal menghitung total dengan benar
  - uji baris non-transaksi (`Total`, `Uang Bersih`, `Saldo`) dan pastikan tidak masuk daftar transaksi tersimpan
  - uji anti-duplikasi: simpan draf yang sama 2x dalam 72 jam, pastikan muncul dialog konfirmasi duplikasi hash
  - pastikan transaksi dari jalur chat import tersimpan dengan tag audit sumber (`[chat_import:<hash8>]`)
  - setelah simpan sukses, uji `SnackBar` aksi `Urungkan` dan pastikan transaksi rollback via audit log.
  - simpan dari layar review dan validasi jumlah transaksi tersimpan sesuai item terpilih.
- [ ] Uji UX batch 1 chat-import/OCR review:
  - pastikan aksi `Set IN/Set OUT` tidak memaksa semua item chat-import (item dengan sinyal tipe kuat tetap dipertahankan).
  - pastikan baris tombol aksi review tidak overflow di layar mobile kecil.
- [ ] Uji UX bubble chat user:
  - tombol `Salin` pada bubble user menyalin teks user.
  - tombol `Edit` pada bubble user mengisi ulang input untuk kirim ulang (riwayat lama tidak ditimpa).
- [ ] Uji UX batch 2 (persona & flow chat):
  - sapaan awal chatbot menampilkan identitas "Asisten Mom Fiqry".
  - uji small-talk dasar (`halo`, `tes`, `selamat pagi`, `apa kabar`) dan pastikan bot membalas singkat lalu tetap mengarah ke fungsi finansial.
  - uji pertanyaan `kamu bisa apa` / `bantuan` dan pastikan bot menjelaskan kemampuan + batasan akses.
  - dari tombol `Tanya Lanjutan`, pastikan pertanyaan masuk sebagai prefill input (tidak langsung terkirim).
  - saat ada riwayat chat lama, pastikan muncul pilihan `Lanjutkan` vs `Mulai Baru` sebelum prefill diterapkan.
- [ ] Uji UX batch 3 (assistive parser & confirm-to-review):
  - paste daftar transaksi mentah tanpa trigger eksplisit, pastikan bot tetap mencoba parse action import.
  - jika parse gagal, pastikan bot menjelaskan penyebab + contoh format koreksi (bukan langsung guardrail umum).
  - uji input nominal typo `20.00020.000`, pastikan parser lokal menormalkan nominal ke `20000`.
  - uji inferensi tanggal:
    - blok atas sebelum tanggal eksplisit diasumsikan H-1 dan ditandai review,
    - baris setelah tanggal eksplisit tanpa tanggal melanjutkan tanggal terakhir,
  - jika tidak ada tanggal sama sekali, fallback ke tanggal hari ini + `date_source=inferred`.
  - untuk action import sukses, pastikan chat menampilkan ringkasan + tombol `Lanjut ke Review` (tidak auto-push ke layar OCR).
- [ ] Uji analysis-mode enhancement:
  - kirim pertanyaan komparatif multi-intent (contoh: "berapa penghasilan kemarin, hari ini, bandingkan, analisis dan saran") dan pastikan jawaban lebih detail dari mode ringkas biasa.
  - pastikan jawaban detail tetap menyertakan basis data (tidak halusinasi angka).
  - kirim input sangat panjang (>3500 karakter), pastikan bot tidak crash dan memberi arahan split pertanyaan menjadi beberapa langkah.
- [ ] Uji deterministic stock ranking:
  - tanya "urutkan stok tertinggi-ke-terendah tanpa stok 0" dan pastikan hasil tidak menyebut item `stock_now == 0`.
  - pastikan urutan benar-benar descending berdasarkan angka `stock_now` (bukan urut alfabet).
  - uji `top N` (contoh: `top 5`) dan pastikan jumlah item sesuai.
- [ ] Uji intent router berjenjang:
  - jalankan `flutter test test/chat_intent_router_test.dart` untuk validasi 40+ kasus intent (typo/singkatan/slang).
  - verifikasi query `kamu bisa apa`/`halo` selalu lewat local template (bukan drift ke LLM analitik).
  - verifikasi query ambigu pendek (`cek`, `tolong`) mengembalikan klarifikasi opsi intent.
- [ ] Uji parser tanggal hybrid (lokal + normalizer):
  - verifikasi `N hari lalu` (contoh 2/4/5 hari lalu) mengarah ke tanggal benar.
  - verifikasi query rentang (`dari 01-02-2026 sampai 03-02-2026`) dan explicit date (`2026-02-24`) menghasilkan agregasi sesuai `daily_summary`.
  - verifikasi komparasi (`2 hari lalu vs kemarin`) tidak fallback ke pasangan default `hari ini vs kemarin`.
- [ ] Uji explainability chatbot:
  - verifikasi indikator mode eksekusi muncul di bubble asisten (local/local+ai/llm) dan dapat ditekan untuk melihat detail.
  - pastikan mode `local_ai` muncul saat parser tanggal butuh normalisasi AI namun nominal tetap dihitung lokal.
  - verifikasi bottom sheet informasi indikator tidak menutupi area system navigation bar Android (gesture/3-button).
- [ ] Uji smart search chatbot:
  - query `cari kategori pengeluaran di atas 50 ribu` menampilkan hasil filter kategori dari snapshot lokal.
  - query `cari produk`/`tampilkan riwayat harian` tidak memaksa jalur LLM saat data lokal cukup.
- [ ] Uji hybrid intent router (hard vs soft):
  - hard-intent ambigu (contoh tanggal mentah tanpa metrik) harus memunculkan klarifikasi lokal kontekstual (stok/arus kas/import), bukan fallback AI classifier.
  - soft-intent ambigu harus melewati AI classifier dulu; klarifikasi muncul hanya saat confidence rendah.
  - uji frasa identitas/memori (`siapa nama mu`, `siapa nama ku`, `nama ku ...`) agar tidak jatuh ke klarifikasi generik.
- [ ] Uji OCR fallback transparency log:
  - setelah scan, panel log harus menampilkan urutan model/provider yang dicoba dengan status (`Trying/Success/Failed`), alasan, dan latency.
  - verifikasi fallback case (contoh model utama kena limit) menampilkan penyebab eksplisit per langkah.
- [ ] Jalankan regression test otomatis Phase 4:
  - `flutter test test/chat_import_draft_model_test.dart test/chat_import_audit_service_test.dart`
- [ ] Jalankan regression test OCR parity Phase 1:
  - `flutter test test/ocr_transaction_draft_model_test.dart`
- [ ] Jalankan regression test OCR parity Phase 2:
  - `flutter test test/ocr_post_processing_test.dart`
- [ ] Jalankan regression test OCR parity Phase 3:
  - `flutter test test/ocr_import_audit_service_test.dart`
- [ ] Jalankan regression test OCR parity Phase 4 (reliability edge cases):
  - `flutter test test/ocr_post_processing_test.dart test/ocr_transaction_draft_model_test.dart test/ocr_import_audit_service_test.dart`

## 12) Lessons Learned (Codex Fast Path)
- Kasus import package test sempat gagal karena typo nama package.
  - Nama package yang benar: `mom_fikri_cashflow` (cek cepat: `rg -n "^name:" pubspec.yaml`).
  - Sebelum buat file test baru, samakan pola import dengan test existing di folder `test/`.
- Kasus `flutter test` sempat gagal akses lockfile SDK (`/opt/homebrew/.../flutter/bin/cache/lockfile`) saat jalan di sandbox.
  - Fast path: jalankan `flutter test` dengan izin escalated (akses ke path SDK di luar workspace).
  - Hindari asumsi perlu `sudo chown`; di environment ini `sudo` non-interaktif sering gagal karena butuh password TTY.
- Urutan eksekusi yang lebih efisien untuk penambahan test:
  1. Verifikasi nama package dari `pubspec.yaml`.
  2. Tambah test file.
  3. Jalankan hanya test target (bukan full suite) untuk feedback cepat.
  4. Jika lolos, baru update `CHANGELOG.md`/`WORKFLOW.md` dan commit.
