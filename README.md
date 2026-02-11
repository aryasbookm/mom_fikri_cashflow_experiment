# Mom Fiqry Cashflow

Aplikasi **Point of Sale (POS)** dan **Manajemen Stok** berbasis Flutter yang dikembangkan untuk membantu operasional "Toko Kue Mom Fiqry". Proyek ini merupakan bagian dari penelitian Skripsi.

## 📌 Fitur Utama (v1.0.0)
- **Kasir & Transaksi:** Multi-item cart, struk digital, dan validasi stok real-time.
- **Manajemen Stok Cerdas:** Pelacakan stok otomatis, alert stok menipis, dan audit trail.
- **Keamanan Data:** Sistem Backup/Restore `.zip` (database + foto produk) dengan validasi integritas & rollback, tetap kompatibel restore `.db` lama.
- **Cloud Android:** Backup/Restore paket backup ke Google Drive (`appDataFolder`).
- **Keamanan Akses:** PIN Guard untuk menu sensitif (Owner) dan isolasi data Staff.
- **Laporan & Analitik:** Dashboard performa harian, Top Produk, dan ekspor laporan (PDF/Excel).

## 📂 Navigasi Dokumentasi (Skripsi)
Repositori ini dilengkapi dengan dokumentasi teknis dan operasional sebagai berikut:

### 1. Riwayat & Evolusi
- **[CHANGELOG.md](CHANGELOG.md)**: Catatan lengkap evolusi fitur berdasarkan fase pengembangan (Timeline: v0.9.0 hingga v1.0.0-rc3). **(Baca ini untuk melihat progres skripsi)**.

### 2. Spesifikasi Teknis
- **[spec.md](spec.md)**: Spesifikasi teknis mendalam, termasuk Skema Database SQLite (v8) dan arsitektur State Management.
- **[PROJECT_NOTES.md](PROJECT_NOTES.md)**: Catatan keputusan desain, daftar fitur, dan strategi pengembangan.

### 3. Protokol & Pengujian
- **[TESTING_BACKUP_RESTORE.md](TESTING_BACKUP_RESTORE.md)**: Dokumen User Acceptance Test (UAT) khusus untuk fitur kritikal Backup & Restore.
- **[AGENTS.md](AGENTS.md)**: Dokumentasi mengenai role dan aturan kerja AI Agent yang membantu pengembangan proyek ini.
- **[AI_CONTEXT.md](AI_CONTEXT.md)**: Konteks lintas-sesi universal untuk semua AI (role boundary, technical map, quality gate).

## 🤖 SOP AI Collaboration (Ringkas)
- Best-practice check dijalankan **default** untuk perubahan non-trivial (tanpa menunggu keyword).
- Timebox blocker: maksimal **3 percobaan** atau **45–60 menit**, lalu pivot ke alternatif paling aman.
- Quality gate sebelum merge: **Happy Path + Edge Case + Rollback/Recovery**.
- Update dokumen memakai prinsip **impacted docs only** (hindari noise).

## 🚀 Cara Menjalankan Aplikasi

### Prasyarat
- Flutter SDK (Latest Stable)
- Dart SDK

### Instalasi
```bash
# 1. Clone atau download repositori ini
# 2. Masuk ke direktori proyek
cd mom_fiqry_cashflow_experiment

# 3. Instal dependensi
flutter pub get

# 4. Jalankan aplikasi (pilih device target)
flutter run
```

Dikembangkan oleh Aryasaputra untuk Skripsi 2026.
