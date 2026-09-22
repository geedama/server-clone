#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR=""
TARGET_IP=""

while (($#)); do
  case "$1" in
    --from) SOURCE_DIR="$2"; shift 2 ;;
    --target-ip) TARGET_IP="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 || -z "$SOURCE_DIR" || -z "$TARGET_IP" ]]; then
  echo "Usage: restore.sh --from DIR --target-ip IP (run as root)" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_DIR/backup-meta.env" ]]; then
  echo "Backup metadata is missing." >&2
  exit 1
fi

source_ip="$(sed -n 's/^SOURCE_IP=//p' "$SOURCE_DIR/backup-meta.env")"

systemctl disable --now codex-web.service hysteria2.service 3proxy-pac.service firefox-pac.service 2>/dev/null || true

for item in .codex .agents .local .npm .config codex-web hy2-firefox-proxy; do
  if [[ -e "$SOURCE_DIR/$item" ]]; then
    mkdir -p "/home/cooper/$item"
    rsync -aH --delete "$SOURCE_DIR/$item/" "/home/cooper/$item/"
  fi
done

chown -R cooper:cooper \
  /home/cooper/.codex \
  /home/cooper/.agents \
  /home/cooper/.local \
  /home/cooper/.npm \
  /home/cooper/.config \
  /home/cooper/codex-web \
  /home/cooper/hy2-firefox-proxy

chmod 700 /home/cooper/.codex
chmod 600 /home/cooper/.codex/auth.json /home/cooper/codex-web/codex-web.env

vpn_dir=/home/cooper/hy2-firefox-proxy
if [[ -n "$source_ip" ]]; then
  sed -i -E "s/server: ${source_ip//./\\.}:38443/server: $TARGET_IP:38443/" \
    "$vpn_dir/config/hysteria-test-client.yaml"
  sed -i -E "s/[[:space:]]+-e${source_ip//./\\.}([[:space:]]|$)/ /" \
    "$vpn_dir/config/3proxy.cfg"
  sed -i -E "s#HTTPS ${source_ip//./\\.}:443#HTTPS proxy.local:443#" \
    "$vpn_dir/pac/proxy.pac"
fi

install -o root -g root -m 0644 \
  /home/cooper/codex-web/codex-web.service \
  /etc/systemd/system/codex-web.service

install -d -o root -g root -m 0755 /etc/systemd/system/codex-web.service.d
cat >/etc/systemd/system/codex-web.service.d/90-full-root-access.conf <<'EOF'
[Service]
Environment="PATH=/home/cooper/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
NoNewPrivileges=false
PrivateTmp=false
PrivateDevices=false
ProtectSystem=false
ProtectHome=false
ProtectClock=false
ProtectControlGroups=false
ProtectHostname=false
ProtectKernelLogs=false
ProtectKernelModules=false
ProtectKernelTunables=false
CapabilityBoundingSet=~
LockPersonality=false
RemoveIPC=false
RestrictAddressFamilies=
RestrictRealtime=false
RestrictSUIDSGID=false
EOF

for unit in hysteria2 3proxy-pac firefox-pac; do
  install -o root -g root -m 0644 \
    "$vpn_dir/systemd/$unit.service" \
    "/etc/systemd/system/$unit.service"
done

chmod 755 "$vpn_dir/bin/hysteria" "$vpn_dir/bin/3proxy" "$vpn_dir/pac-server.py"

systemctl daemon-reload
systemctl enable --now codex-web.service hysteria2.service 3proxy-pac.service firefox-pac.service

ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'Firefox PAC'
ufw allow 443/tcp comment 'Authenticated HTTPS proxy'
ufw allow 38443/udp comment 'Hysteria2'
ufw allow 3001/tcp comment 'Codex Web'
ufw --force enable

curl -fsS http://127.0.0.1:3001/healthz >/dev/null
curl -fsS http://127.0.0.1/proxy.pac >/dev/null
sudo -u cooper -H /home/cooper/.local/bin/codex --version
systemctl --no-pager --full status codex-web.service hysteria2.service 3proxy-pac.service firefox-pac.service

cat <<EOF

Restore completed.
Codex Web: http://$TARGET_IP:3001
PAC:       http://$TARGET_IP/proxy.pac
Hysteria:  $TARGET_IP:38443/udp

To retain the existing HTTPS proxy certificate, clients must resolve:
$TARGET_IP proxy.local
EOF
