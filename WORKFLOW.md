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
