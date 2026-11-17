# SysGuard — Backup & Monitoring Layanan (Pilihan A)

Proyek Akhir Praktikum Sistem Operasi: Otomasi dan Container Linux.

**Nama kelompok / kelas:** Kelompok 3 / Kelas D

**Anggota (nama, NIM):**

- Andra Bimo Wiguna (2510501132)
- Muhammad Sami (2510501127)
- Diandra Satrio Nugroho (2510501123)
- Muhammad Fikri Riswaluyo (2510501117)
- Divo Dimas Saputra (2510501110)

## 1. Tujuan
SysGuard memastikan sebuah layanan web tetap sehat dan datanya dapat dipulihkan.
Dua modul saling terhubung:

| Modul | Fungsi |
|---|---|
| **Monitoring** (`scripts/monitor.sh`) | Memeriksa layanan (container + HTTP 200) dan kapasitas storage backup (persentase terpakai + ruang kosong). |
| **Backup & Restore** (`scripts/backup.sh`, `scripts/restore.sh`) | Membuat arsip tar.gz + manifest + checksum, mengirimnya via SCP, lalu memulihkan dan **memverifikasi** hasil restore. |

**Integrasi:** hasil monitoring menjadi *gate*. Jika layanan tidak sehat atau storage
tidak memadai, backup **ditolak** (exit 20). Setiap restore diverifikasi dengan checksum
archive dan manifest per-file.

## 2. Kebutuhan lingkungan

- Linux dengan Bash, `tar`, `sha256sum`, `curl`, `flock`, `openssh-client` (`ssh`, `scp`, `ssh-keygen`)
- Docker Engine + Docker Compose v2
- Port host `8080` dan `2222` bebas (hanya di-bind ke `127.0.0.1`)

## 3. Arsitektur

```
HOST (skrip shell)                          DOCKER (network sysguard-net 172.28.0.0/24)
┌────────────────────────┐   HTTP 8080     ┌──────────────────────────┐
│ scripts/sysguard.sh    │ ───────────────▶│ sysguard-web  (nginx)    │
│  ├ monitor.sh          │                 │  bind mount ./data/www:ro│
│  ├ backup.sh ──gate──┐ │                 │  0.5 CPU, 128 MB         │
│  └ restore.sh        │ │  SSH/SCP 2222   ├──────────────────────────┤
│ var/state (checksum) │ └────────────────▶│ sysguard-store (sshd)    │
│ var/log, var/restore │                   │  volume backup_data      │
│ secrets/ (key SSH)   │                   │  volume ssh_hostkeys     │
└────────────────────────┘                 │  0.5 CPU, 64 MB          │
                                           └──────────────────────────┘
```

**Pembagian host vs container**

| Di host | Di container |
|---|---|
| Skrip orkestrasi, validasi, logging aktivitas, catatan checksum lokal, hasil restore | `web`: layanan yang dimonitor, sumber data (bind mount, read-only) |
| Key SSH privat (`secrets/`, tidak di-commit) | `backup-store`: server SSH/SFTP, penyimpanan backup (volume) |

**Alur backup:** `monitor.sh` (layanan + disk) → *gagal: tolak* / *lulus:* arsip + manifest + checksum
→ `scp` ke store → `sha256sum -c` di store → catat checksum di host.  
**Alur restore:** ambil dari store → cek checksum archive (dibanding catatan host) → cek isi archive aman
(tanpa path absolut / `..`) → ekstrak → cek tiap file dengan manifest → (opsional `--apply`).

## 4. Instalasi

```bash
git clone <URL-REPOSITORY> sysguard && cd sysguard
cp config/sysguard.conf.example config/sysguard.conf     # tanpa rahasia
./scripts/setup-ssh.sh                                    # buat key ed25519 di secrets/
docker compose build
docker compose up -d
docker compose ps                                         # web: healthy, backup-store: running
```

## 5. Menjalankan

```bash
./scripts/sysguard.sh monitor            # cek layanan + storage
./scripts/sysguard.sh backup             # backup (ditolak bila monitoring gagal)
./scripts/sysguard.sh list               # daftar backup di store
./scripts/sysguard.sh restore            # restore + verifikasi backup terbaru
./scripts/sysguard.sh restore -b backup-YYYYMMDD-HHMMSS
./scripts/sysguard.sh run                # alur integrasi: monitor → backup → restore
```

Stop dan buat ulang container (tunjukkan build/run/stop/recreate):

```bash
docker compose stop
docker compose up -d
docker compose rm -sf backup-store && docker compose up -d backup-store   # dibuat ulang
```

## 6. Menguji

```bash
./scripts/tests/run-tests.sh
```

Skrip menjalankan tes **aktual** dan menulis `evidence/hasil-uji.md` (tabel siap masuk laporan)
dan `evidence/logs/<ID>.log` (output mentah). Tes yang tidak dapat dijalankan ditandai `SKIP`,
tidak pernah dianggap lulus.

| ID | Cakupan |
|---|---|
| M-01..M-04 | Monitoring: sehat, layanan mati, disk melewati ambang, input tidak valid |
| B-01..B-04 | Backup: sukses, **ditolak** saat layanan mati / disk penuh, sumber tidak aman |
| R-01..R-03 | Restore: sukses, archive rusak (checksum), nama tidak valid |
| I-01 | **Integrasi**: monitoring → backup → data dihapus → restore → isi identik |
| S-01..S-05 | Akses SSH: key sah diterima; key asing, password, root **ditolak**; permission file 600 |
| C-01..C-04 | Resource limit, tanpa privileged/docker.sock, persistensi setelah container dibuat ulang, monitoring container |

Pemeriksaan manual pelengkap (untuk screenshot):

```bash
docker inspect -f '{{.Name}} cpus={{.HostConfig.NanoCpus}} mem={{.HostConfig.Memory}}' sysguard-web sysguard-store
docker stats --no-stream
./scripts/sysguard.sh monitor --stats     # snapshot stats + log container ke var/log/container-monitor.log
tail -n 30 var/log/sysguard.log           # log aktivitas
```

## 7. Konfigurasi & exit status

Konfigurasi di `config/sysguard.conf` (contoh: `config/sysguard.conf.example`); variabel
environment mengalahkan file (mis. `MAX_DISK_PCT=1 ./scripts/sysguard.sh backup`).

| Kode | Arti |
|---|---|
| 0 | Sukses |
| 2 / 3 | Argumen atau konfigurasi tidak valid / dependensi hilang |
| 10 / 11 / 12 | Layanan tidak sehat / storage tidak memadai / store tidak terjangkau |
| 20 / 21 | Backup **ditolak** preflight / backup gagal |
| 30 / 31 / 32 / 33 | Checksum archive salah / isi tidak cocok manifest / path tidak aman / backup tidak ada |
| 40 | Ada backup lain yang sedang berjalan |

## 8. Cleanup

```bash
docker compose down                    # hentikan & hapus container (volume tetap)
docker compose down -v                 # + hapus volume backup (SEMUA backup hilang)
rm -rf var/                            # log, staging, hasil restore, catatan checksum lokal
docker image rm sysguard-web:1.0 sysguard-store:1.0
```

## 9. Rollback

- **Data sumber salah terpulihkan:** `restore --apply` selalu menyalin isi lama ke
  `var/rollback/pre-restore-<waktu>/` sebelum menimpa. Kembalikan dengan
  `cp -a var/rollback/pre-restore-<waktu>/. data/www/`.
- **Backup baru bermasalah:** hapus berkas `backup-<waktu>.*` di store; backup lama tidak tersentuh:
  `ssh -i secrets/sysguard_backup -p 2222 backup@127.0.0.1 'rm -f /backups/sysguard/backup-<waktu>.*'`.
- **Konfigurasi container:** `git checkout <tag-sebelumnya>` lalu `docker compose up -d --build`.

## 10. Keamanan

- Akses store hanya SSH key (ed25519); password, root login, dan forwarding dinonaktifkan.
- Berkas backup mode `600`; `var/state` dan `var/staging` mode `700`.
- Container tanpa `privileged`, tanpa Docker socket, `cap_drop: ALL`, `no-new-privileges`, port hanya `127.0.0.1`.
- `SOURCE_DIR` wajib di bawah `<repo>/data/` sehingga data sistem/pribadi tidak tersentuh.
- Semua nilai konfigurasi divalidasi (whitelist) sebelum dirangkai ke perintah remote.
- Tidak ada credential di repo (`secrets/`, `var/`, `config/sysguard.conf` ada di `.gitignore`).

## 11. Keterbatasan

- Key SSH tanpa passphrase agar otomasi berjalan (lab); produksi sebaiknya memakai passphrase/agent atau key khusus terbatas.
- Skrip di host belum otomatis terjadwal (cron/systemd timer belum dibuat).
- Tidak ada retensi/rotasi backup otomatis dan tidak ada enkripsi archive.
- Checksum mendeteksi perubahan/kerusakan, bukan pelaku. Pembandingnya disimpan di host (`var/state`); jika direktori itu hilang, verifikasi memakai checksum dari store saja (dicatat sebagai WARN).
- Pengguna `backup` dapat menjalankan perintah shell di container store (dibutuhkan untuk `df`/verifikasi); belum dibatasi `ForceCommand`.
- Mode `STORE_MODE=local` hanya untuk pengembangan tanpa Docker; bukan untuk bukti pengujian.
- `backup-store` memerlukan capability tambahan `DAC_OVERRIDE` dan `FOWNER` (selain CHOWN, SETUID, SETGID, SYS_CHROOT, KILL) agar entrypoint dapat menyiapkan `~/.ssh` milik user backup; container tetap tanpa `privileged`.

## 12. Kontribusi anggota

| Anggota | NIM | Komponen yang dikerjakan | Bukti (commit/berkas) |
|---|---|---|---|
| Andra Bimo Wiguna | 2510501132 | Repository dan Git, orkestrasi `sysguard.sh`, README, menjalankan tes; perbaikan kompatibilitas Linux (`common.sh`, `backup.sh`, `docker-compose.yml`) | commit a3e5870, `evidence/hasil-uji.md`, `evidence/logs/run-tests.log` |
| Muhammad Sami | 2510501127 | Modul Monitoring: `scripts/monitor.sh`, `scripts/lib/common.sh` | uji M-01..M-04 (`evidence/logs/M-*.log`) |
| Diandra Satrio Nugroho | 2510501123 | Modul Backup dan Restore: `scripts/backup.sh`, `scripts/restore.sh` | uji B-01..B-04, R-01..R-03, I-01 (`evidence/logs/`) |
| Muhammad Fikri Riswaluyo | 2510501117 | Akses aman: `scripts/setup-ssh.sh`, `docker/backup-store/sshd_config` | uji S-01..S-05 (`evidence/logs/S-*.log`) |
| Divo Dimas Saputra | 2510501110 | Container: Dockerfile, `docker-compose.yml`, volume, network, resource limit | uji C-01..C-04 (`evidence/logs/C-*.log`) |

## 13. Struktur repository

```
scripts/        sysguard.sh monitor.sh backup.sh restore.sh setup-ssh.sh lib/common.sh tests/run-tests.sh
docker/         web/ (nginx) backup-store/ (sshd)
docker-compose.yml  config/  data/www/ (data simulasi)  docs/  evidence/
```
