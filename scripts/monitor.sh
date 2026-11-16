#!/usr/bin/env bash
# scripts/monitor.sh -- Modul 1: monitoring layanan + kapasitas storage.
# Hasilnya menjadi GATE bagi backup.sh.
#
# Exit: 0 sehat | 10 layanan bermasalah | 11 storage tidak memadai |
#       12 store tidak terjangkau | 2 argumen salah | 3 dependensi hilang
set -uo pipefail
SG_COMPONENT=monitor
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<EOF
Pemakaian: monitor.sh [--stats] [-h]
  (tanpa opsi)  periksa layanan dan kapasitas storage; exit status sesuai hasil
  --stats       tambahan: catat snapshot docker stats + log container ke
                var/log/container-monitor.log (bukti monitoring container)
EOF
}

container_check_enabled() {
  case $CHECK_CONTAINER in
    yes) return 0 ;;
    no)  return 1 ;;
    auto) command -v docker >/dev/null 2>&1 && docker inspect "$SERVICE_CONTAINER" >/dev/null 2>&1 ;;
  esac
}

check_service() {
  if container_check_enabled; then
    local running health
    running=$(docker inspect -f '{{.State.Running}}' "$SERVICE_CONTAINER" 2>/dev/null || echo false)
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$SERVICE_CONTAINER" 2>/dev/null || echo none)
    if [[ $running != true ]]; then
      log ERROR "container $SERVICE_CONTAINER TIDAK berjalan"; return "$E_SERVICE"
    fi
    log INFO "container $SERVICE_CONTAINER running (health=$health)"
  fi
  local code
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$SERVICE_URL" || true)
  if [[ $code != 200 ]]; then
    log ERROR "layanan $SERVICE_URL tidak sehat (HTTP $code)"; return "$E_SERVICE"
  fi
  log INFO "layanan $SERVICE_URL sehat (HTTP 200)"
}

check_storage() {
  local line total used avail pct src_kb need
  if ! line=$(store_exec "mkdir -p '$STORE_DIR' && df -Pk '$STORE_DIR' | tail -n 1"); then
    log ERROR "backup store tidak dapat dijangkau (mode=$STORE_MODE)"; return "$E_STORE_DOWN"
  fi
  read -r _ total used avail pct _ <<<"$line"
  pct=${pct%\%}
  if ! is_int "$pct" || ! is_int "$avail"; then
    log ERROR "output df tidak dapat dibaca: '$line'"; return "$E_STORE_DOWN"
  fi
  src_kb=$(du -sk "$SOURCE_DIR" | cut -f1)
  need=$((src_kb * MIN_FREE_FACTOR))
  log INFO "storage: terpakai=${pct}% (batas ${MAX_DISK_PCT}%), tersedia=${avail}KB, dibutuhkan>=${need}KB"
  if ((pct >= MAX_DISK_PCT)); then
    log ERROR "penggunaan disk ${pct}% >= batas ${MAX_DISK_PCT}%"; return "$E_STORAGE"
  fi
  if ((avail < need)); then
    log ERROR "ruang tersedia ${avail}KB < dibutuhkan ${need}KB"; return "$E_STORAGE"
  fi
}

snapshot_stats() {
  command -v docker >/dev/null 2>&1 || die "$E_DEP" "docker tidak tersedia untuk --stats"
  local out="$LOG_DIR/container-monitor.log" c
  {
    echo "===== $(date '+%F %T') docker stats ====="
    docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}' \
      "$SERVICE_CONTAINER" "$STORE_CONTAINER" 2>&1
    for c in "$SERVICE_CONTAINER" "$STORE_CONTAINER"; do
      echo "----- docker logs --tail 15 $c -----"
      docker logs --tail 15 "$c" 2>&1
    done
  } | tee -a "$out"
  log INFO "snapshot monitoring container ditulis ke $out"
}

main() {
  local stats=no
  while (($#)); do
    case $1 in
      --stats) stats=yes ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit "$E_USAGE" ;;
    esac
    shift
  done
  require_cmd curl du df
  sg_init
  validate_source_dir || exit $?
  [[ $stats == yes ]] && { snapshot_stats; }

  local rc_svc=0 rc_sto=0
  check_service || rc_svc=$?
  check_storage || rc_sto=$?

  local s_svc=OK s_sto=OK
  ((rc_svc == 0)) || s_svc=FAIL
  ((rc_sto == 0)) || s_sto=FAIL
  printf 'SERVICE=%s STORAGE=%s\n' "$s_svc" "$s_sto"

  ((rc_svc != 0)) && exit "$rc_svc"
  ((rc_sto != 0)) && exit "$rc_sto"
  log INFO "monitoring: semua pemeriksaan LULUS"
  exit 0
}
main "$@"
