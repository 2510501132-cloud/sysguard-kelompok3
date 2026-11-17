| ID uji | Modul/fitur | Kondisi/input | Hasil yang diharapkan | Hasil aktual | Status | Lokasi bukti |
|---|---|---|---|---|---|---|
| M-01 | Monitoring | Layanan hidup, disk store di bawah batas | exit 0, SERVICE=OK STORAGE=OK | exit=0; 2026-11-17 05:42:59 [INFO] [monitor] monitoring: semua pemeriksaan LULUS | PASS | evidence/logs/M-01.log |
| M-02 | Monitoring | Layanan dihentikan | exit 10, SERVICE=FAIL | exit=10; SERVICE=FAIL STORAGE=OK | PASS | evidence/logs/M-02.log |
| M-03 | Monitoring | Ambang disk diturunkan (MAX_DISK_PCT=1) | exit 11, STORAGE=FAIL | exit=11; SERVICE=OK STORAGE=FAIL | PASS | evidence/logs/M-03.log |
| M-04 | Monitoring | Input tidak valid (MAX_DISK_PCT=abc) | exit 2, pesan validasi | exit=2; 2026-11-17 05:43:02 [ERROR] [monitor] MAX_DISK_PCT harus bilangan 1-100 (nilai: 'abc') | PASS | evidence/logs/M-04.log |
| B-01 | Backup | Preflight lulus | exit 0, BACKUP_NAME tercetak, tersimpan di store | exit=0; BACKUP_NAME=backup-20261117-054303 | PASS | evidence/logs/B-01.log |
| B-02 | Backup+Monitoring | Backup saat layanan mati | exit 20 (DITOLAK), tidak ada backup baru | exit=20; 2026-11-17 05:43:06 [ERROR] [backup] BACKUP DITOLAK: preflight monitoring gagal (kode 10) | PASS | evidence/logs/B-02.log |
| B-02b | Backup+Monitoring | Jumlah backup setelah B-02 | jumlah tidak bertambah (2) | exit=0; 2 | PASS | evidence/logs/B-02b.log |
| B-03 | Backup+Monitoring | Disk store melewati ambang (MAX_DISK_PCT=1) | exit 20 (DITOLAK) | exit=20; 2026-11-17 05:43:09 [ERROR] [backup] BACKUP DITOLAK: preflight monitoring gagal (kode 11) | PASS | evidence/logs/B-03.log |
| B-04 | Backup | SOURCE_DIR di luar data/ (/etc) | exit 32, ditolak | exit=32; 2026-11-17 05:43:09 [ERROR] [backup] SOURCE_DIR '/etc' di luar /home/bimoserver/sysguard-k | PASS | evidence/logs/B-04.log |
| R-01 | Restore | Restore backup terbaru | exit 0, RESTORE_VERIFIED | exit=0; RESTORE_VERIFIED name=backup-20261117-054303 files=4 dest=/home/bimoserver/sysguard-kelomp | PASS | evidence/logs/R-01.log |
| R-02 | Restore | Archive di store dirusak (1 byte ditambahkan) | exit 30, checksum tidak cocok | exit=30; 2026-11-17 05:43:14 [ERROR] [restore] CHECKSUM ARCHIVE TIDAK COCOK -- archive berubah/rusa | PASS | evidence/logs/R-02.log |
| R-03 | Restore | Nama backup tidak valid (../../etc) | exit 2 | exit=2; 2026-11-17 05:43:14 [ERROR] [restore] nama backup tidak valid: '../../etc' | PASS | evidence/logs/R-03.log |
| I-01 | Integrasi | Monitoring->backup->hapus data->restore --apply->bandingkan isi | exit 0, berkas pulih identik | exit=0; INTEGRASI OK: berkas pulih, isi identik | PASS | evidence/logs/I-01.log |
| S-01 | Akses aman | SSH dengan key yang diizinkan | exit 0, 'akses-ok' | exit=0; akses-ok | PASS | evidence/logs/S-01.log |
| S-02 | Akses aman | SSH dengan key yang TIDAK terdaftar | ditolak (Permission denied) | exit=255; backup@127.0.0.1: Permission denied (publickey). | PASS | evidence/logs/S-02.log |
| S-03 | Akses aman | Login dengan password | ditolak (password auth nonaktif) | exit=255; backup@127.0.0.1: Permission denied (publickey). | PASS | evidence/logs/S-03.log |
| S-04 | Akses aman | Login sebagai root | ditolak | exit=255; root@127.0.0.1: Permission denied (publickey). | PASS | evidence/logs/S-04.log |
| S-05 | Akses aman | Permission file backup di store | mode 600, pemilik backup | exit=0; 600 bimoserver /home/bimoserver/sysguard-kelompok3/var/state/backup-20261117-054316.tar.gz | PASS | evidence/logs/S-05.log |
| C-01 | Container | Batas CPU/memori diterapkan | NanoCpus & Memory > 0; docker stats tampil | exit=0; sysguard-store CPU=0.00% MEM=1.406MiB / 64MiB PIDS=1 | PASS | evidence/logs/C-01.log |
| C-02 | Container | Tidak privileged & tanpa docker.sock | Privileged=false, tidak ada docker.sock | exit=0; sysguard-store Privileged=false Mounts=/var/lib/docker/volumes/sysguard_backup_data/_data  | PASS | evidence/logs/C-02.log |
| C-03 | Container+Persistensi | Container backup-store dibuat ulang | backup tetap ada, host key tetap, restore terverifikasi | exit=0; RESTORE_VERIFIED name=backup-20261117-054316 files=4 dest=/home/bimoserver/sysguard-kelomp | PASS | evidence/logs/C-03.log |
| C-04 | Monitoring container | Snapshot docker stats + log container | exit 0, log tercatat | exit=0; 2026-11-17 05:43:28 [INFO] [monitor] monitoring: semua pemeriksaan LULUS | PASS | evidence/logs/C-04.log |
