# THESIS_REVISION_RULES.md

Aturan operasional revisi skripsi untuk menjaga konsistensi naskah dengan aplikasi aktual.

## 1) Prinsip Utama Revisi
- Pertahankan gaya dan struktur teks asli sejauh mungkin (revisi konservatif).
- Ubah hanya bagian yang berisiko dipatahkan saat sidang (over-claim, mismatch fitur, istilah tidak presisi).
- Semua klaim fitur harus bisa dibuktikan lewat demo, kode, atau tabel pengujian.
- Hindari perubahan besar mendadak yang membuat pembimbing kesulitan mengikuti jejak revisi.

## 2) Aturan Sinkronisasi dengan Aplikasi
- Jangan menulis fitur sebagai "sudah diimplementasikan" jika tidak ada di aplikasi aktif.
- Fokus kontribusi inti pada:
  - pencatatan terintegrasi (pemasukan, pengeluaran, produksi),
  - pengelolaan kategori terstruktur,
  - kontrol akses role-based + PIN owner,
  - backup/restore (lokal dan cloud) dengan behavior aman,
  - pendekatan offline-first.
- Jika ada fitur yang belum final, tulis sebagai:
  - keterbatasan sistem saat ini, atau
  - rencana pengembangan lanjutan.

## 3) Aturan Istilah Teknis
- Gunakan istilah:
  - "dikembangkan menggunakan framework Flutter",
  - "aplikasi berbasis mobile (implementasi Android)".
- Hindari frasa utama:
  - "berbasis Flutter" sebagai basis platform.
- Konsistenkan istilah lintas bab:
  - owner/staff,
  - backup/restore,
  - offline-first,
  - role-based access,
  - kategori sistem/custom.

## 3.1) Kamus Istilah Baku (Gunakan Konsisten)
- Aplikasi: `aplikasi pencatatan keuangan berbasis mobile (Android), dikembangkan menggunakan framework Flutter`.
- Platform: `mobile (Android)` sebagai fokus implementasi penelitian.
- Database: `basis data lokal (SQLite)`.
- Fitur inti: `pencatatan pemasukan, pengeluaran, dan produksi`.
- Kategori: `pengelolaan kategori transaksi terstruktur`.
- Akses: `kontrol akses berbasis peran pengguna`.
- Proteksi data: `mekanisme backup dan restore data`.
- Output informasi: `ringkasan saldo harian`, `rekapitulasi transaksi`, `laporan sederhana`.
- Istilah peran di naskah: gunakan `pemilik` dan `karyawan` (boleh tulis `(owner)`/`(staff)` pada penyebutan awal jika perlu).
- Istilah yang dihindari sebagai kontribusi inti:
  - `klasifikasi transaksi otomatis berbasis rule/kata kunci` (kecuali disebut sebagai landasan konseptual/future work),
  - `berbasis Flutter` sebagai frasa utama platform.

## 4) Aturan Klaim Akademik
- Dilarang menggunakan klaim absolut tanpa bukti:
  - "bebas kesalahan fatal",
  - "meningkat signifikan",
  - "terbukti optimal".
- Ganti dengan klaim defensif berbasis data uji:
  - "berdasarkan skenario pengujian yang dilakukan, ...".
- Semua kalimat hasil harus ditautkan ke tabel/gambar/skenario uji.

## 5) Aturan Waterfall (Traceability Wajib)
- Bab II: teori Waterfall boleh tetap ada.
- Bab III: wajib ada penerapan nyata per fase (analisis, desain, implementasi, pengujian, evaluasi/pemeliharaan).
- Bab IV: wajib ada bukti hasil per fase (diagram, implementasi, tabel uji, pembahasan).
- Gunakan tabel ringkas:
  - fase Waterfall -> aktivitas -> artefak -> bukti di naskah.

## 6) Aturan Pengujian (Wajib untuk Sidang)
- Black-box tidak cukup hanya 4-5 skenario; perlu cakupan fitur kritikal.
- UAT wajib kuantitatif:
  - jumlah responden,
  - item per aspek,
  - skala,
  - rumus nilai,
  - hasil akhir (persentase/kategori).
- Sertakan minimal:
  - happy path,
  - edge case,
  - recovery/rollback.

## 7) Aturan Revisi Per Bab
- Bab I:
  - pastikan masalah, tujuan, pertanyaan, dan batasan saling konsisten,
  - hindari janji fitur yang tidak ada.
- Bab II:
  - teori harus mendukung fitur yang benar-benar ada,
  - teori yang tidak diimplementasikan diposisikan sebagai opsi/future work.
- Bab III:
  - jelaskan metode dan instrumen secara operasional, bukan umum.
  - jika dosen meminta penghapusan subbab, hapus seluruh cakupan subbab dan lakukan renumber subbab berikutnya + sinkronisasi Daftar Isi.
  - setiap tabel jadwal/prosedur wajib memiliki keterangan (legend) dan sumber data.
- Bab IV:
  - prioritaskan bukti hasil, bukan deskripsi panjang tanpa data.
- Bab V:
  - kesimpulan harus menjawab pertanyaan penelitian secara langsung dan terukur.

## 8) Aturan Konsistensi Dokumen
- Cek konsistensi antara naskah skripsi dan dokumen proyek:
  - `THESIS_REFERENCE.md`,
  - `PROJECT_NOTES.md`,
  - `spec.md`,
  - `CHANGELOG.md`.
- Jika ada konflik informasi versi/fitur, selesaikan dulu sebelum lanjut revisi bab berikutnya.

## 9) Protokol Kerja Revisi
- Kerjakan bertahap per bab (Bab I -> Bab II -> Bab III -> Bab IV -> Bab V).
- Setiap tahap harus menghasilkan:
  - daftar perubahan inti,
  - alasan perubahan,
  - risiko jika tidak diubah.
- Simpan jejak perubahan secara minim-dif (agar mudah direview pembimbing).

## 9.1) Log Progres Revisi (Wajib Update Tiap Kesepakatan)
- Setiap keputusan revisi yang disetujui harus langsung dicatat.
- Format minimal log:
  - bagian/bab yang diubah,
  - ringkasan perubahan,
  - alasan akademik/teknis,
  - status (`done`, `pending`, `deferred`),
  - tanggal keputusan.
- Tujuan: menjaga konsistensi lintas sesi dan memudahkan laporan progres ke pembimbing.

## 9.2) Aturan Deferred/Skipped Item
- Jika ada bagian yang sengaja dilangkahi sementara, wajib dicatat sebagai `deferred`.
- Untuk setiap item `deferred`, tulis:
  - alasan ditunda,
  - prasyarat agar bisa dikerjakan,
  - target bab/tahap lanjutan.
- Contoh: "2.1 Kerangka Pikir ditunda karena perlu melihat gambar final terlebih dahulu."

## 9.3) Aturan Pindah/Hapus Konten
- Jika ada konten yang dihapus, ringkas alasan penghapusan:
  - redundan,
  - over-claim,
  - tidak sinkron dengan implementasi,
  - dipindah ke bab lain.
- Jika ada konten dipindah antar bab, catat:
  - asal konten,
  - tujuan bab baru,
  - alasan pemindahan.
- Prinsip: tidak ada perubahan besar tanpa jejak keputusan.

## 10) Format Anotasi Revisi Dosen (Wajib Dipakai Saat Kolaborasi)
- Format minimal yang dipakai user saat mengirim teks:
  - `{REVISI} ... {/REVISI}` untuk bagian teks yang ditandai,
  - `[ARAHAN] ... [/ARAHAN]` untuk instruksi revisi dari dosen.
- Format tambahan (opsional, hanya jika perlu):
  - `[CAKUPAN] ... [/CAKUPAN]` bila arahan berlaku lebih luas dari teks yang ditandai,
  - `[PRIORITAS] tinggi/sedang/rendah [/PRIORITAS]`,
  - `[NOTE] ... [/NOTE]` untuk komentar/konteks tambahan dari user,
  - `[CATATAN] ... [/CATATAN]` jika user ragu menafsirkan maksud dosen.
- Jika `[CAKUPAN]` tidak ada, reviewer tetap wajib melakukan inferensi konteks secara konservatif.

## 11) Aturan Interpretasi Catatan Dosen
- Jangan menerima interpretasi user 100% mentah tanpa validasi akademik dan teknis.
- Jika catatan dosen ambigu, lakukan:
  1. inferensi konteks lokal (paragraf/subbab terkait),
  2. cek konsistensi dengan fitur aplikasi aktual,
  3. pilih revisi paling defensif untuk sidang.
- Jika ketidakpastian masih tinggi, tandai sebagai asumsi terbuka sebelum finalisasi subbab.
- Prinsip default: perbaiki secukupnya agar aman, jangan memperluas revisi tanpa alasan kuat.

## 12) Definisi Selesai (Definition of Done)
- Narasi naskah sinkron dengan aplikasi aktual.
- Tidak ada over-claim fitur.
- Waterfall terlacak dari metode sampai hasil.
- Uji fungsional dan UAT memiliki bukti yang cukup.
- Istilah teknis konsisten dari Bab I sampai Bab V.
- Log progres revisi lengkap dan dapat diaudit.
- Nomor subbab/tabel konsisten setelah ada penghapusan/pemindahan bagian.
