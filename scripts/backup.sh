#!/usr/bin/env bash
# scripts/backup.sh -- Modul 2a: backup ke store, DIGATE oleh monitor.sh.
#
# Alur: preflight (monitor.sh) -> arsip tar.gz + manifest + checksum -> upload
#       (SCP) -> verifikasi checksum di sisi store.
# Exit: 0 sukses | 20 DITOLAK preflight | 21 gagal | 32 sumber tidak aman |
#       2 argumen | 3 dependensi | 40 sudah ada backup berjalan
# stdout: BACKUP_NAME=<nama>
set -uo pipefail
SG_COMPONENT=backup
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() { echo "Pemakaian: backup.sh [-h]   (konfigurasi: config/sysguard.conf / environment)"; }

case ${1:-} in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit "$E_USAGE" ;;
esac

require_cmd tar sha256sum find sort xargs flock du curl date
sg_init
[[ $STORE_MODE == ssh ]] && require_cmd ssh scp
validate_source_dir || exit $?

exec 9>"$STATE_DIR/.backup.lock"
flock -n 9 || die "$E_LOCK" "backup lain sedang berjalan"

# ---- 1. Preflight: hasil monitoring menentukan lanjut / tolak ------------------
log INFO "preflight: menjalankan monitor.sh"
"$SG_ROOT/scripts/monitor.sh"; rc=$?
if ((rc != 0)); then
  log ERROR "BACKUP DITOLAK: preflight monitoring gagal (kode $rc)"
  exit "$E_REJECTED"
fi
log INFO "preflight lulus -- backup dilanjutkan"

# ---- 2. Buat arsip -------------------------------------------------------------
name="backup-$(date +%Y%m%d-%H%M%S)"
uploaded=0; ok=0
cleanup() {
  rm -f "$STAGING_DIR/$name".tar.gz "$STAGING_DIR/$name".tar.gz.sha256 "$STAGING_DIR/$name".manifest.sha256
  if ((ok == 0 && uploaded == 1)); then
    log WARN "membersihkan file parsial di store"
    store_exec "cd '$STORE_DIR' && rm -f '$name.tar.gz' '$name.tar.gz.sha256' '$name.manifest.sha256'" || true
  fi
}
trap cleanup EXIT

if store_exec "test -e '$STORE_DIR/$name.tar.gz'"; then
  die "$E_BACKUP_FAIL" "nama backup $name sudah ada di store (coba lagi 1 detik kemudian)"
fi

umask 077   # file staging & di store hanya dapat dibaca pemilik
log INFO "membuat arsip $name dari $SOURCE_DIR"
( cd "$SOURCE_DIR" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum ) \
  >"$STAGING_DIR/$name.manifest.sha256" || die "$E_BACKUP_FAIL" "gagal membuat manifest"
tar -C "$SOURCE_DIR" -czf "$STAGING_DIR/$name.tar.gz" . || die "$E_BACKUP_FAIL" "gagal membuat arsip tar"
( cd "$STAGING_DIR" && sha256sum "$name.tar.gz" >"$name.tar.gz.sha256" ) \
  || die "$E_BACKUP_FAIL" "gagal membuat checksum"
nfiles=$(wc -l <"$STAGING_DIR/$name.manifest.sha256")
log INFO "arsip dibuat: $nfiles file, $(du -k "$STAGING_DIR/$name.tar.gz" | cut -f1)KB"

# ---- 3. Upload + verifikasi di sisi store -------------------------------------
uploaded=1
store_put "$STAGING_DIR/$name.tar.gz" "$STAGING_DIR/$name.tar.gz.sha256" "$STAGING_DIR/$name.manifest.sha256" \
  || die "$E_BACKUP_FAIL" "upload ke store gagal"
store_exec "cd '$STORE_DIR' && sha256sum -c --quiet '$name.tar.gz.sha256'" \
  || die "$E_BACKUP_FAIL" "verifikasi checksum di store gagal"

# Catatan checksum disimpan juga di host (terpisah dari store) sebagai pembanding saat restore.
cp -- "$STAGING_DIR/$name.tar.gz.sha256" "$STAGING_DIR/$name.manifest.sha256" "$STATE_DIR/"

ok=1
log INFO "BACKUP BERHASIL: $name ($nfiles file) tersimpan & terverifikasi di store"
echo "BACKUP_NAME=$name"
