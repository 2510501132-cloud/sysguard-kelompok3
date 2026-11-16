#!/usr/bin/env bash
# scripts/sysguard.sh -- CLI utama SysGuard (Pilihan A: Backup & Monitoring Layanan)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SG_COMPONENT=cli
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

usage() {
  cat <<EOF
SysGuard -- monitoring layanan + backup/restore terverifikasi

Pemakaian: sysguard.sh <perintah> [opsi]
  monitor [--stats]        periksa layanan & kapasitas storage
  backup                   backup (ditolak jika monitoring gagal)
  restore [-b NAMA] [--apply]
                           restore + verifikasi (default: backup terbaru)
  list                     daftar backup di store
  run                      alur integrasi: monitor -> backup -> restore terverifikasi
  -h, --help               bantuan ini
Exit status: lihat README (tabel exit status).
EOF
}

cmd=${1:-}; [[ $# -gt 0 ]] && shift
case $cmd in
  monitor) exec "$DIR/monitor.sh" "$@" ;;
  backup)  exec "$DIR/backup.sh" "$@" ;;
  restore) exec "$DIR/restore.sh" "$@" ;;
  list)
    sg_init
    store_exec "ls -1 '$STORE_DIR' 2>/dev/null | grep -E '^backup-[0-9]{8}-[0-9]{6}\.tar\.gz\$' | sed 's/\.tar\.gz\$//' | sort" ;;
  run)
    out=$("$DIR/backup.sh") || exit $?
    echo "$out"
    name=$(sed -n 's/^BACKUP_NAME=//p' <<<"$out")
    [[ -n $name ]] || die "$E_BACKUP_FAIL" "nama backup tidak terbaca"
    "$DIR/restore.sh" -b "$name" ;;
  -h|--help|"") usage ;;
  *) usage >&2; exit "$E_USAGE" ;;
esac
