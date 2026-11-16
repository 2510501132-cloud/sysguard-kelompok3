#!/bin/sh
# Menyiapkan host key (persisten di volume) dan authorized_keys, lalu menjalankan sshd.
set -eu
HK=/etc/ssh/hostkeys/ssh_host_ed25519_key
[ -f "$HK" ] || ssh-keygen -q -t ed25519 -N '' -f "$HK"
chmod 600 "$HK"
if [ ! -f /run/keys/backup.pub ]; then
  echo "public key /run/keys/backup.pub tidak ada -- jalankan scripts/setup-ssh.sh dulu" >&2
  exit 1
fi
install -d -m 700 -o backup -g backup /home/backup/.ssh
install -m 600 -o backup -g backup /run/keys/backup.pub /home/backup/.ssh/authorized_keys
exec /usr/sbin/sshd -D -e
