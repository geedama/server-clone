#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_REPO="${BACKUP_REPO:-geedama/server-clone-backup}"
SOURCE_HOME="${SOURCE_HOME:-/home/cooper}"

for cmd in gh age zstd rsync tar sha256sum; do
  command -v "$cmd" >/dev/null || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
done

gh auth status >/dev/null
gh repo view "$BACKUP_REPO" >/dev/null

work_dir="$(mktemp -d)"
snapshot_dir="$work_dir/snapshot"
asset="$work_dir/codex-server-backup.tar.zst.age"
checksum="$asset.sha256"
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$snapshot_dir"

items=(
  .codex
  .agents
  .local
  .npm
  .config
  codex-web
  hy2-firefox-proxy
)

echo "Creating a consistent snapshot..."
for item in "${items[@]}"; do
  if [[ -e "$SOURCE_HOME/$item" ]]; then
    mkdir -p "$snapshot_dir/$item"
    rsync -aH --delete "$SOURCE_HOME/$item/" "$snapshot_dir/$item/"
  fi
done

source_ip="$(ip -4 -o addr show scope global | awk '$2 != "docker0" {split($4,a,"/"); print a[1]; exit}')"
cat >"$snapshot_dir/backup-meta.env" <<EOF
BACKUP_FORMAT=1
SOURCE_USER=cooper
SOURCE_IP=$source_ip
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo
echo "Choose a strong encryption passphrase. It will not be saved or uploaded."
tar -C "$snapshot_dir" -cpf - . | zstd -T0 -10 | age -p -o "$asset"
chmod 600 "$asset"

(
  cd "$work_dir"
  sha256sum "$(basename "$asset")" >"$(basename "$checksum")"
)

asset_size="$(stat -c %s "$asset")"
if (( asset_size >= 2147483648 )); then
  echo "Encrypted asset is 2 GiB or larger; refusing GitHub Release upload." >&2
  exit 1
fi

tag="backup-$(date -u +%Y%m%d-%H%M%S)"
echo "Uploading encrypted backup as release $tag..."
gh release create "$tag" "$asset" "$checksum" \
  --repo "$BACKUP_REPO" \
  --title "$tag" \
  --notes "Encrypted Codex, Codex Web, and VPN/PAC backup."

echo
echo "Published: https://github.com/$BACKUP_REPO/releases/tag/$tag"
echo "Keep the encryption passphrase safe; GitHub cannot recover it."
