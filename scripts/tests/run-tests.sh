#!/usr/bin/env bash
# scripts/tests/run-tests.sh -- pengujian otomatis SysGuard.
# Menjalankan skenario berhasil/gagal + integrasi + akses + persistensi + resource limit,
# menulis log mentah ke evidence/logs/<ID>.log dan tabel ke evidence/hasil-uji.md.
# Semua hasil berasal dari eksekusi aktual; tes yang tidak dapat dijalankan ditandai SKIP.
#
# Pemakaian: scripts/tests/run-tests.sh        (mode ssh + Docker = pengujian penuh)
#            STORE_MODE=local ... (dev tanpa Docker; tes SSH/container -> SKIP)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT" || exit 1
CLI="$ROOT/scripts/sysguard.sh"
EVID="$ROOT/evidence/logs"; TABLE="$ROOT/evidence/hasil-uji.md"
mkdir -p "$EVID"
export SG_ROOT_FOR_TESTS="$ROOT"

# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"
SG_COMPONENT=tests
sg_init
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
HAS_DOCKER=no
[[ $STORE_MODE == ssh ]] && docker inspect "$SERVICE_CONTAINER" >/dev/null 2>&1 && HAS_DOCKER=yes

{
  echo "| ID uji | Modul/fitur | Kondisi/input | Hasil yang diharapkan | Hasil aktual | Status | Lokasi bukti |"
  echo "|---|---|---|---|---|---|---|"
} >"$TABLE"
pass=0; fail=0; skip=0

# t ID MODUL KONDISI DIHARAPKAN EXIT_DIHARAPKAN POLA_OUTPUT CMD...
t() {
  local id=$1 mod=$2 cond=$3 exp=$4 want=$5 pat=$6; shift 6
  local out rc st last
  out=$("$@" 2>&1); rc=$?
  { printf '# %s -- %s\n# %s\n$ %s\n' "$id" "$mod" "$cond" "$*"; printf '%s\n[exit status = %s]\n' "$out" "$rc"; } >"$EVID/$id.log"
  if ((rc == want)) && [[ -z $pat || $out =~ $pat ]]; then st=PASS; ((pass++)); else st=FAIL; ((fail++)); fi
  last=$(printf '%s' "$out" | grep -v '^$' | tail -n 1 | cut -c1-90 | sed 's/|/\//g')
  printf '| %s | %s | %s | %s | exit=%s; %s | %s | evidence/logs/%s.log |\n' \
    "$id" "$mod" "$cond" "$exp" "$rc" "$last" "$st" "$id" >>"$TABLE"
  echo "[$st] $id exit=$rc"
}
skipt() { # ID MODUL KONDISI ALASAN
  printf '| %s | %s | %s | - | tidak dijalankan: %s | SKIP | - |\n' "$1" "$2" "$3" "$4" >>"$TABLE"
  echo "[SKIP] $1 ($4)"; ((skip++))
}

svc_stop()  { if [[ $HAS_DOCKER == yes ]]; then docker compose stop web >/dev/null 2>&1; fi; }
svc_start() { if [[ $HAS_DOCKER == yes ]]; then docker compose start web >/dev/null 2>&1
              for _ in $(seq 1 20); do [[ $(curl -s -o /dev/null -w '%{http_code}' -m 2 "$SERVICE_URL") == 200 ]] && break; sleep 1; done; fi; }
# Menjalankan perintah selagi layanan 'mati' (container dihentikan; mode local: URL tak terjangkau)
while_service_down() {
  local rc
  if [[ $HAS_DOCKER == yes ]]; then
    svc_stop; "$@"; rc=$?; svc_start
  else
    SERVICE_URL=http://127.0.0.1:9/ "$@"; rc=$?
  fi
  return $rc
}
count_backups() { "$CLI" list 2>/dev/null | grep -c '^backup-' || true; }
latest_name()   { "$CLI" list 2>/dev/null | tail -n 1; }

# ============================ MODUL MONITORING =================================
t M-01 "Monitoring" "Layanan hidup, disk store di bawah batas" "exit 0, SERVICE=OK STORAGE=OK" 0 'SERVICE=OK STORAGE=OK' "$CLI" monitor
t M-02 "Monitoring" "Layanan dihentikan" "exit 10, SERVICE=FAIL" 10 'SERVICE=FAIL' while_service_down "$CLI" monitor
t M-03 "Monitoring" "Ambang disk diturunkan (MAX_DISK_PCT=1)" "exit 11, STORAGE=FAIL" 11 'STORAGE=FAIL' env MAX_DISK_PCT=1 "$CLI" monitor
t M-04 "Monitoring" "Input tidak valid (MAX_DISK_PCT=abc)" "exit 2, pesan validasi" 2 'MAX_DISK_PCT' env MAX_DISK_PCT=abc "$CLI" monitor

# ============================ MODUL BACKUP =====================================
sleep 1
t B-01 "Backup" "Preflight lulus" "exit 0, BACKUP_NAME tercetak, tersimpan di store" 0 'BACKUP_NAME=backup-' "$CLI" backup
n_before=$(count_backups)
sleep 1
t B-02 "Backup+Monitoring" "Backup saat layanan mati" "exit 20 (DITOLAK), tidak ada backup baru" 20 'BACKUP DITOLAK' while_service_down "$CLI" backup
n_after=$(count_backups)
if [[ $n_before == "$n_after" ]]; then
  t B-02b "Backup+Monitoring" "Jumlah backup setelah B-02" "jumlah tidak bertambah ($n_before)" 0 "^$n_before\$" echo "$n_after"
else
  t B-02b "Backup+Monitoring" "Jumlah backup setelah B-02" "jumlah tidak bertambah ($n_before)" 0 "^$n_before\$" echo "$n_after (berubah!)"
fi
t B-03 "Backup+Monitoring" "Disk store melewati ambang (MAX_DISK_PCT=1)" "exit 20 (DITOLAK)" 20 'BACKUP DITOLAK' env MAX_DISK_PCT=1 "$CLI" backup
t B-04 "Backup" "SOURCE_DIR di luar data/ (/etc)" "exit 32, ditolak" 32 'ditolak' env SOURCE_DIR=/etc "$CLI" backup

# ============================ MODUL RESTORE ====================================
t R-01 "Restore" "Restore backup terbaru" "exit 0, RESTORE_VERIFIED" 0 'RESTORE_VERIFIED' "$CLI" restore
sleep 1
corrupt_test() {
  local out name
  out=$("$CLI" backup) || return 99
  name=$(sed -n 's/^BACKUP_NAME=//p' <<<"$out")
  store_exec "printf 'x' >> '$STORE_DIR/$name.tar.gz'" || return 98
  "$CLI" restore -b "$name"
}
t R-02 "Restore" "Archive di store dirusak (1 byte ditambahkan)" "exit 30, checksum tidak cocok" 30 'CHECKSUM ARCHIVE TIDAK COCOK' corrupt_test
t R-03 "Restore" "Nama backup tidak valid (../../etc)" "exit 2" 2 'tidak valid' "$CLI" restore -b ../../etc

# ============================ INTEGRASI ========================================
sleep 1
integration_test() {
  local f="$SOURCE_DIR/docs/notes.txt" out name
  cp -a "$f" "$TMP/orig"
  echo "marker-integrasi-$(date +%s)" >>"$f"; cp -a "$f" "$TMP/modified"
  out=$("$CLI" backup) || { cp -a "$TMP/orig" "$f"; return 99; }
  name=$(sed -n 's/^BACKUP_NAME=//p' <<<"$out")
  rm -f "$f"; echo "[info] berkas sumber dihapus (simulasi kehilangan data)"
  "$CLI" restore -b "$name" --apply || { cp -a "$TMP/orig" "$f"; return 98; }
  if cmp -s "$f" "$TMP/modified"; then echo "INTEGRASI OK: berkas pulih, isi identik"; rc=0; else echo "INTEGRASI GAGAL: isi berbeda"; rc=1; fi
  cp -a "$TMP/orig" "$f"   # kembalikan data contoh ke kondisi awal
  return $rc
}
t I-01 "Integrasi" "Monitoring->backup->hapus data->restore --apply->bandingkan isi" "exit 0, berkas pulih identik" 0 'INTEGRASI OK' integration_test

# ============================ AKSES AMAN (SSH) =================================
if [[ $STORE_MODE == ssh ]]; then
  t S-01 "Akses aman" "SSH dengan key yang diizinkan" "exit 0, 'akses-ok'" 0 'akses-ok' store_exec "echo akses-ok"
  ssh-keygen -q -t ed25519 -N '' -f "$TMP/intruder" >/dev/null
  intruder() { ssh -n -i "$TMP/intruder" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" true; }
  t S-02 "Akses aman" "SSH dengan key yang TIDAK terdaftar" "ditolak (Permission denied)" 255 'Permission denied' intruder
  pwauth() { ssh -n -o BatchMode=yes -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" true; }
  t S-03 "Akses aman" "Login dengan password" "ditolak (password auth nonaktif)" 255 'Permission denied' pwauth
  rootlogin() { ssh -n -i "$SSH_KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" -p "$SSH_PORT" root@"$SSH_HOST" true; }
  t S-04 "Akses aman" "Login sebagai root" "ditolak" 255 'Permission denied' rootlogin
  perm_test() {
    local name; name=$(latest_name)
    echo "store : $(store_exec "stat -c '%a %U:%G %n' '$STORE_DIR/$name.tar.gz' '$STORE_DIR'")"
    echo "host  : $(stat -c '%a %U %n' "$STATE_DIR" "$STATE_DIR/$name.tar.gz.sha256")"
    [[ $(store_exec "stat -c '%a' '$STORE_DIR/$name.tar.gz'") == 600 ]]
  }
  t S-05 "Akses aman" "Permission file backup di store" "mode 600, pemilik backup" 0 '600 backup' perm_test
else
  for id in S-01 S-02 S-03 S-04 S-05; do skipt "$id" "Akses aman" "pengujian SSH" "STORE_MODE=local"; done
fi

# ============================ CONTAINER ========================================
if [[ $HAS_DOCKER == yes ]]; then
  limits_test() {
    local c
    for c in "$SERVICE_CONTAINER" "$STORE_CONTAINER"; do
      docker inspect -f '{{.Name}} NanoCpus={{.HostConfig.NanoCpus}} Memory={{.HostConfig.Memory}} PidsLimit={{.HostConfig.PidsLimit}}' "$c"
    done
    docker stats --no-stream --format '{{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}} PIDS={{.PIDs}}' "$SERVICE_CONTAINER" "$STORE_CONTAINER"
    [[ $(docker inspect -f '{{.HostConfig.NanoCpus}}' "$SERVICE_CONTAINER") -gt 0 && $(docker inspect -f '{{.HostConfig.Memory}}' "$SERVICE_CONTAINER") -gt 0 ]]
  }
  t C-01 "Container" "Batas CPU/memori diterapkan" "NanoCpus & Memory > 0; docker stats tampil" 0 'NanoCpus=' limits_test
  hardening_test() {
    local c rc=0
    for c in "$SERVICE_CONTAINER" "$STORE_CONTAINER"; do
      echo "$c Privileged=$(docker inspect -f '{{.HostConfig.Privileged}}' "$c") Mounts=$(docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "$c")"
      [[ $(docker inspect -f '{{.HostConfig.Privileged}}' "$c") == false ]] || rc=1
      docker inspect -f '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' "$c" | grep -q 'docker.sock' && rc=1
    done
    return $rc
  }
  t C-02 "Container" "Tidak privileged & tanpa docker.sock" "Privileged=false, tidak ada docker.sock" 0 'Privileged=false' hardening_test
  persist_test() {
    local name before after
    name=$(latest_name); before=$(count_backups)
    docker compose rm -sf backup-store >/dev/null 2>&1 && docker compose up -d backup-store >/dev/null 2>&1 || return 90
    for _ in $(seq 1 20); do store_exec true >/dev/null 2>&1 && break; sleep 1; done
    after=$(count_backups)
    echo "container dibuat ulang; backup sebelum=$before sesudah=$after; terbaru=$name"
    [[ $before == "$after" ]] || return 91
    "$CLI" restore -b "$name"
  }
  t C-03 "Container+Persistensi" "Container backup-store dibuat ulang" "backup tetap ada, host key tetap, restore terverifikasi" 0 'RESTORE_VERIFIED' persist_test
  t C-04 "Monitoring container" "Snapshot docker stats + log container" "exit 0, log tercatat" 0 'docker stats' "$CLI" monitor --stats
  cp -f "$LOG_DIR/container-monitor.log" "$EVID/C-04-container-monitor.log" 2>/dev/null || true
else
  for id in C-01 C-02 C-03 C-04; do skipt "$id" "Container" "resource limit/persistensi/monitoring container" "container belum berjalan / STORE_MODE=local"; done
fi

cp -f "$LOG_DIR/sysguard.log" "$EVID/sysguard-activity.log" 2>/dev/null || true
echo
echo "RINGKASAN: PASS=$pass FAIL=$fail SKIP=$skip  (tabel: evidence/hasil-uji.md)"
((fail == 0))
