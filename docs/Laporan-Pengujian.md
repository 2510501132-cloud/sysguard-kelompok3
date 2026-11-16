# Laporan Pengujian — SysGuard

_Template. Ekspor ke **Laporan-Pengujian.pdf** setelah semua bagian terisi dari hasil aktual. Jangan mengulang isi README._

## 1. Identitas dan pilihan proyek
- Nama kelompok dan kelas: 
- Anggota (nama, NIM): 
- Pilihan proyek: **A — Backup dan Monitoring Layanan**
- Judul proyek: SysGuard — Backup & Monitoring Layanan
- Repository / commit ID lengkap / tag final: 

## 2. Ringkasan fungsi kedua modul
- **Modul Monitoring:** memeriksa container + HTTP layanan dan kapasitas storage; hasilnya (exit status 0/10/11/12) menjadi gate backup.
- **Modul Backup & Restore:** arsip tar.gz + manifest + checksum, transfer SCP, verifikasi di store, restore terverifikasi (checksum archive + manifest per-file).
- **Integrasi:** backup ditolak (exit 20) bila monitoring gagal; restore diverifikasi sebelum diterapkan.

## 3. Tabel pengujian
Salin isi `evidence/hasil-uji.md` hasil `./scripts/tests/run-tests.sh` yang dijalankan **pada commit final**.

| ID uji | Modul/fitur | Kondisi/input | Hasil yang diharapkan | Hasil aktual | Status | Lokasi bukti |
|---|---|---|---|---|---|---|
| | | | | | | |

Bukti tambahan (screenshot yang didukung command/log): `docker compose ps`, `docker inspect` limit, `docker stats`, `monitor --stats`, percobaan SSH ditolak.

## 4. Interpretasi hasil dan keterbatasan
- Tulis apa arti tiap kelompok hasil (mis. B-02/B-03 membuktikan gate monitoring bekerja; R-02 membuktikan korupsi archive terdeteksi).
- Tes berstatus FAIL/SKIP: jelaskan penyebab dan tindakannya.
- Keterbatasan: salin/ringkas bagian 11 README yang relevan.

## 5. Kontribusi setiap anggota
| Anggota | NIM | Kontribusi | Bukti |
|---|---|---|---|
| | | | |
