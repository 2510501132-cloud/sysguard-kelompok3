# Outline Slide (maks. 8) — ekspor ke Slide-Presentasi.pdf

1. **Judul & tim** — SysGuard, Pilihan A, anggota + NIM.
2. **Masalah** — layanan bisa mati / disk penuh saat backup; backup tanpa verifikasi tidak dapat dipercaya.
3. **Arsitektur** — diagram host vs container (dari README bagian 3), alur gate monitoring → backup.
4. **Modul Monitoring** — pemeriksaan layanan + disk, exit status, contoh output.
5. **Modul Backup & Restore** — arsip, manifest, checksum, SCP, verifikasi restore.
6. **Keamanan, persistensi, resource limit** — SSH key, izin 600, volume, limit CPU/mem, tanpa privileged.
7. **Hasil pengujian** — ringkasan PASS/FAIL, satu kondisi berhasil vs gagal (B-01 vs B-02/R-02), integrasi I-01.
8. **Kesimpulan & keterbatasan** — apa yang tercapai, apa yang belum, rencana lanjutan.
