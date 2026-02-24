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
    - `--dart-define=AI_PROVIDER_ORDER=gemini,groq`
  - opsional model: `--dart-define=GEMINI_MODEL=gemini-2.5-flash`
  - opsional model fallback:
    - `--dart-define=GROQ_VISION_MODEL=llama-3.2-11b-vision-preview`

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
