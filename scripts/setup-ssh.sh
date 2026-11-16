#!/usr/bin/env bash
# scripts/setup-ssh.sh -- membuat key pair ed25519 untuk akses backup (sekali saja).
# Key privat TIDAK boleh di-commit (secrets/ ada di .gitignore).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
KEY="$ROOT/secrets/sysguard_backup"
mkdir -p -m 700 "$ROOT/secrets"
if [[ -f $KEY ]]; then
  echo "Key sudah ada: $KEY (tidak ditimpa)"
else
  # Tanpa passphrase agar skrip dapat berjalan otomatis (lab). Lihat keterbatasan di README.
  ssh-keygen -q -t ed25519 -N '' -C "sysguard-backup" -f "$KEY"
  echo "Key dibuat: $KEY(.pub)"
fi
chmod 600 "$KEY"; chmod 644 "$KEY.pub"
