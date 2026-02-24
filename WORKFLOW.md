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
  - simpan dari layar review dan validasi jumlah transaksi tersimpan sesuai item terpilih.
- [ ] Jalankan regression test otomatis Phase 4:
  - `flutter test test/chat_import_draft_model_test.dart test/chat_import_audit_service_test.dart`
- [ ] Jalankan regression test OCR parity Phase 1:
  - `flutter test test/ocr_transaction_draft_model_test.dart`
- [ ] Jalankan regression test OCR parity Phase 2:
  - `flutter test test/ocr_post_processing_test.dart`
- [ ] Jalankan regression test OCR parity Phase 3:
  - `flutter test test/ocr_import_audit_service_test.dart`

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
