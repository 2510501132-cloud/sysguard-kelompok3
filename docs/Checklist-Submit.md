# Checklist sebelum submit (Assignment P15)

## Dijalankan di mesin kelompok (butuh Docker)
- [ ] `./scripts/setup-ssh.sh && docker compose up -d --build` berhasil; `docker compose ps` sehat
- [ ] `./scripts/tests/run-tests.sh` → tidak ada FAIL, tidak ada SKIP (semua S-xx dan C-xx jalan)
- [ ] Jika ada kegagalan (mis. sshd/nginx gagal naik karena `cap_drop`/`read_only`): perbaiki, jalankan ulang, catat di laporan
- [ ] Ambil screenshot: `docker compose ps`, `docker inspect` limit, `docker stats`, SSH ditolak, hasil restore
- [ ] Salin `evidence/` hasil run final (log + screenshot), pastikan tidak ada credential

## Repository
- [ ] Semua anggota sudah commit bagian masing-masing (cek `git shortlog -sn`)
- [ ] Tidak ada `secrets/`, key privat, atau data pribadi di repo (`git ls-files | grep -i secret`)
- [ ] Repo dapat diakses dosen
- [ ] Tag final: `git tag P2-FINAL-v01 && git push --tags`; catat commit ID lengkap (`git rev-parse HEAD`)

## ZIP: `Kelas-KelompokXX-SysGuard-Final.zip`
- [ ] `source/` (isi sama dengan commit final, tanpa `var/`, `secrets/`)
- [ ] `README.md` (nama, anggota, kontribusi sudah terisi)
- [ ] `Laporan-Pengujian.pdf`
- [ ] `evidence/`
- [ ] `Slide-Presentasi.pdf` (≤ 8 slide)

## Online Text
Nama kelompok & kelas · Nama & NIM anggota · Pilihan proyek: A · Judul · URL repo · Commit ID lengkap · Tag final · Cara menjalankan singkat · Fungsi yang berjalan · Keterbatasan

## Terakhir
- [ ] Submission dikirim (bukan Draft) sebelum tenggat di LeADS
