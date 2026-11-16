#!/usr/bin/env bash
# scripts/restore.sh -- Modul 2b: restore + verifikasi hasil restore.
#
# Pemakaian: restore.sh [-b NAMA|latest] [--apply] [-h]
#   -b NAMA   backup yang dipulihkan (default: latest)
#   --apply   setelah terverifikasi, ganti isi SOURCE_DIR dengan hasil restore.
#             Isi lama diselamatkan dulu ke var/rollback/ (lihat README: rollback).
# Exit: 0 terverifikasi | 30 checksum archive salah | 31 isi tidak cocok manifest |
#       32 archive tidak aman | 33 backup tidak ditemukan | 2 | 3
set -uo pipefail
SG_COMPONENT=restore
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() { sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

name=latest; apply=no
while (($#)); do
  case $1 in
    -b) [[ -n ${2:-} ]] || { usage >&2; exit "$E_USAGE"; }; name=$2; shift ;;
    --apply) apply=yes ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit "$E_USAGE" ;;
  esac
  shift
done

require_cmd tar sha256sum find wc mktemp
sg_init
[[ $STORE_MODE == ssh ]] && require_cmd ssh scp

if [[ $name == latest ]]; then
  name=$(store_exec "ls -1 '$STORE_DIR' 2>/dev/null | grep -E '^backup-[0-9]{8}-[0-9]{6}\.tar\.gz\$' | sort | tail -n 1" | sed 's/\.tar\.gz$//')
  [[ -n $name ]] || die "$E_NOTFOUND" "belum ada backup di store"
fi
valid_backup_name "$name" || die "$E_USAGE" "nama backup tidak valid: '$name'"

work=$(mktemp -d "$RESTORE_DIR/.work.XXXXXX") || die "$E_USAGE" "gagal membuat direktori kerja"
trap 'rm -rf "$work"' EXIT

log INFO "mengambil $name dari store"
for f in "$name.tar.gz" "$name.tar.gz.sha256" "$name.manifest.sha256"; do
  store_get "$f" "$work" || die "$E_NOTFOUND" "berkas $f tidak ditemukan / gagal diambil"
done

# ---- 1. Verifikasi checksum archive -------------------------------------------
# Pembanding: catatan lokal di host (jika ada), bukan hanya checksum di store.
ref_sum="$STATE_DIR/$name.tar.gz.sha256"; ref_man="$STATE_DIR/$name.manifest.sha256"
if [[ ! -f $ref_sum ]]; then
  log WARN "catatan checksum lokal tidak ada -- memakai checksum dari store"
  ref_sum="$work/$name.tar.gz.sha256"; ref_man="$work/$name.manifest.sha256"
fi
if ! ( cd "$work" && sha256sum -c --quiet "$ref_sum" ) >/dev/null 2>&1; then
  die "$E_CHECKSUM" "CHECKSUM ARCHIVE TIDAK COCOK -- archive berubah/rusak, restore dibatalkan"
fi
log INFO "checksum archive cocok"

# ---- 2. Pastikan isi archive aman, lalu ekstrak -------------------------------
if tar -tzf "$work/$name.tar.gz" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  die "$E_UNSAFE" "archive memuat path absolut / '..' -- ditolak"
fi
dest="$RESTORE_DIR/$name"
rm -rf -- "$dest"; mkdir -p "$dest"
tar -xzf "$work/$name.tar.gz" -C "$dest" --no-same-owner || die "$E_UNSAFE" "ekstraksi gagal"

# ---- 3. Verifikasi isi hasil restore terhadap manifest ------------------------
if ! ( cd "$dest" && sha256sum -c --quiet "$ref_man" ) >/dev/null 2>&1; then
  die "$E_MANIFEST" "isi hasil restore TIDAK cocok dengan manifest"
fi
expected=$(wc -l <"$ref_man"); actual=$(find "$dest" -type f | wc -l)
((expected == actual)) || die "$E_MANIFEST" "jumlah file tidak cocok (manifest=$expected, hasil=$actual)"
log INFO "RESTORE TERVERIFIKASI: $actual file cocok dengan manifest ($dest)"

# ---- 4. (opsional) terapkan ke SOURCE_DIR dengan rollback aman -----------------
if [[ $apply == yes ]]; then
  validate_source_dir || exit $?
  rb="$SG_ROOT/var/rollback/pre-restore-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$rb" && cp -a "$SOURCE_DIR/." "$rb/" || die "$E_USAGE" "gagal menyimpan salinan rollback"
  log INFO "salinan rollback: $rb"
  find "$SOURCE_DIR" -mindepth 1 -delete
  cp -a "$dest/." "$SOURCE_DIR/" || die "$E_USAGE" "gagal menerapkan hasil restore"
  log INFO "hasil restore diterapkan ke $SOURCE_DIR"
fi

echo "RESTORE_VERIFIED name=$name files=$actual dest=$dest"
