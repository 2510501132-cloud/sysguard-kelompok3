#!/usr/bin/env bash
# scripts/lib/common.sh -- fungsi bersama SysGuard (logging, konfigurasi,
# validasi, akses ke backup store). Di-source oleh script lain, bukan dijalankan.

SG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# ---- Exit status (didokumentasikan di README) --------------------------------
E_OK=0
E_USAGE=2          # argumen / konfigurasi tidak valid
E_DEP=3            # perintah yang dibutuhkan tidak ada
E_SERVICE=10       # layanan tidak sehat
E_STORAGE=11       # kapasitas storage tidak memadai
E_STORE_DOWN=12    # backup store tidak dapat dijangkau
E_REJECTED=20      # backup DITOLAK oleh preflight monitoring
E_BACKUP_FAIL=21   # backup gagal di tengah proses
E_CHECKSUM=30      # checksum archive tidak cocok
E_MANIFEST=31      # verifikasi isi hasil restore gagal
E_UNSAFE=32        # path / isi archive tidak aman
E_NOTFOUND=33      # backup tidak ditemukan
E_LOCK=40          # ada proses lain yang sedang berjalan

LOG_DIR="${LOG_DIR:-$SG_ROOT/var/log}"

# ---- Logging ------------------------------------------------------------------
log() {
  local level=$1; shift
  local line
  line="$(date '+%F %T') [$level] [${SG_COMPONENT:-sysguard}] $*"
  mkdir -p "$LOG_DIR" 2>/dev/null && printf '%s\n' "$line" >>"$LOG_DIR/sysguard.log"
  printf '%s\n' "$line" >&2
}
die() { local code=$1; shift; log ERROR "$*"; exit "$code"; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "$E_DEP" "perintah '$c' tidak ditemukan"
  done
}

abspath() { case $1 in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$SG_ROOT" "$1" ;; esac; }

# ---- Konfigurasi --------------------------------------------------------------
# Membaca KEY=VALUE (KEY huruf besar/underscore). Variabel environment yang sudah
# di-set SELALU menang atas file -- berguna untuk skenario uji (mis. MAX_DISK_PCT=1).
load_config() {
  local f=$1 k v
  [[ -f $f ]] || return 0
  while IFS='=' read -r k v; do
    [[ $k =~ ^[A-Z_]+$ ]] || continue
    v=${v%\"}; v=${v#\"}
    if [[ -z ${!k+x} ]]; then export "$k=$v"; fi
  done < <(grep -Ev '^[[:space:]]*(#|$)' "$f")
}

is_int() { [[ ${1:-} =~ ^[0-9]+$ ]]; }

sg_init() {
  load_config "$(abspath "${SYSGUARD_CONF:-config/sysguard.conf}")"

  : "${STORE_MODE:=ssh}"
  : "${SSH_HOST:=127.0.0.1}" "${SSH_PORT:=2222}" "${SSH_USER:=backup}"
  : "${SSH_KEY:=secrets/sysguard_backup}" "${KNOWN_HOSTS:=secrets/known_hosts}"
  : "${REMOTE_DIR:=/backups/sysguard}" "${LOCAL_STORE_DIR:=var/local-store}"
  : "${SOURCE_DIR:=data/www}"
  : "${SERVICE_URL:=http://127.0.0.1:8080/}" "${SERVICE_CONTAINER:=sysguard-web}"
  : "${STORE_CONTAINER:=sysguard-store}" "${CHECK_CONTAINER:=auto}"
  : "${MAX_DISK_PCT:=90}" "${MIN_FREE_FACTOR:=2}"
  : "${LOG_DIR:=var/log}" "${STAGING_DIR:=var/staging}"
  : "${RESTORE_DIR:=var/restore}" "${STATE_DIR:=var/state}"

  SSH_KEY=$(abspath "$SSH_KEY");         KNOWN_HOSTS=$(abspath "$KNOWN_HOSTS")
  SOURCE_DIR=$(abspath "$SOURCE_DIR");   LOCAL_STORE_DIR=$(abspath "$LOCAL_STORE_DIR")
  LOG_DIR=$(abspath "$LOG_DIR");         STAGING_DIR=$(abspath "$STAGING_DIR")
  RESTORE_DIR=$(abspath "$RESTORE_DIR"); STATE_DIR=$(abspath "$STATE_DIR")

  # Validasi input (nilai ini ikut dirangkai ke perintah remote -> whitelist ketat)
  case $STORE_MODE in ssh|local) ;; *) die "$E_USAGE" "STORE_MODE harus ssh atau local" ;; esac
  case $CHECK_CONTAINER in yes|no|auto) ;; *) die "$E_USAGE" "CHECK_CONTAINER harus yes|no|auto" ;; esac
  is_int "$MAX_DISK_PCT" && ((MAX_DISK_PCT >= 1 && MAX_DISK_PCT <= 100)) \
    || die "$E_USAGE" "MAX_DISK_PCT harus bilangan 1-100 (nilai: '$MAX_DISK_PCT')"
  is_int "$MIN_FREE_FACTOR" && ((MIN_FREE_FACTOR >= 1)) \
    || die "$E_USAGE" "MIN_FREE_FACTOR harus bilangan >= 1"
  is_int "$SSH_PORT" && ((SSH_PORT >= 1 && SSH_PORT <= 65535)) \
    || die "$E_USAGE" "SSH_PORT tidak valid"
  [[ $SSH_HOST =~ ^[A-Za-z0-9._-]+$ ]] || die "$E_USAGE" "SSH_HOST tidak valid"
  [[ $SSH_USER =~ ^[a-z_][a-z0-9_-]*$ ]] || die "$E_USAGE" "SSH_USER tidak valid"
  [[ $REMOTE_DIR =~ ^/[A-Za-z0-9._/-]+$ ]] || die "$E_USAGE" "REMOTE_DIR tidak valid"
  [[ $LOCAL_STORE_DIR =~ ^/[A-Za-z0-9._/-]+$ ]] || die "$E_USAGE" "LOCAL_STORE_DIR tidak valid"
  [[ $SERVICE_URL =~ ^https?://[A-Za-z0-9._:/?=\&%-]+$ ]] || die "$E_USAGE" "SERVICE_URL tidak valid"
  [[ $SERVICE_CONTAINER =~ ^[A-Za-z0-9_.-]+$ ]] || die "$E_USAGE" "SERVICE_CONTAINER tidak valid"

  if [[ $STORE_MODE == ssh ]]; then
    STORE_DIR=$REMOTE_DIR
    SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o IdentitiesOnly=yes
              -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$KNOWN_HOSTS"
              -o ConnectTimeout=5 -o LogLevel=ERROR)
  else
    STORE_DIR=$LOCAL_STORE_DIR
  fi

  mkdir -p "$LOG_DIR" "$RESTORE_DIR"
  mkdir -p -m 700 "$STAGING_DIR" "$STATE_DIR"
}

# Sumber data hanya boleh berada di bawah <repo>/data/ -- mencegah operasi
# menyentuh data sistem atau data pribadi.
validate_source_dir() {
  local real
  real=$(realpath -m -- "$SOURCE_DIR")
  case $real in
    "$SG_ROOT"/data/?*) ;;
    *) log ERROR "SOURCE_DIR '$real' di luar $SG_ROOT/data -- ditolak"; return "$E_UNSAFE" ;;
  esac
  [[ -d $real && -r $real ]] || { log ERROR "SOURCE_DIR tidak ada / tidak terbaca: $real"; return "$E_USAGE"; }
  [[ -n $(find "$real" -type f -print -quit) ]] || { log ERROR "SOURCE_DIR kosong: $real"; return "$E_USAGE"; }
  SOURCE_DIR=$real
}

valid_backup_name() { [[ ${1:-} =~ ^backup-[0-9]{8}-[0-9]{6}$ ]]; }

# ---- Akses ke backup store ----------------------------------------------------
# Mode ssh   : store = container sysguard-store, diakses via SSH/SCP (mode utama).
# Mode local : store = direktori lokal (hanya untuk pengembangan tanpa Docker).
store_exec() { # $1 = perintah shell yang dijalankan di sisi store
  if [[ $STORE_MODE == ssh ]]; then
    ssh -n "${SSH_OPTS[@]}" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "$1"
  else
    mkdir -p "$STORE_DIR" && bash -c "$1"
  fi
}

store_put() { # file...  -> STORE_DIR
  if [[ $STORE_MODE == ssh ]]; then
    scp -q "${SSH_OPTS[@]}" -P "$SSH_PORT" "$@" "$SSH_USER@$SSH_HOST:$STORE_DIR/"
  else
    mkdir -p "$STORE_DIR" && cp -- "$@" "$STORE_DIR/"
  fi
}

store_get() { # nama-file tujuan-dir
  if [[ $STORE_MODE == ssh ]]; then
    scp -q "${SSH_OPTS[@]}" -P "$SSH_PORT" "$SSH_USER@$SSH_HOST:$STORE_DIR/$1" "$2/"
  else
    cp -- "$STORE_DIR/$1" "$2/"
  fi
}
