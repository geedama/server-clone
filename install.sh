#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_REPO="${BACKUP_REPO:-geedama/server-clone-backup}"
TARGET_IP="${TARGET_IP:-}"
RELEASE_TAG="${RELEASE_TAG:-}"

usage() {
  cat <<'EOF'
Usage: install.sh [--target-ip IP] [--backup-repo OWNER/REPO] [--tag TAG]
EOF
}

while (($#)); do
  case "$1" in
    --target-ip) TARGET_IP="$2"; shift 2 ;;
    --backup-repo) BACKUP_REPO="$2"; shift 2 ;;
    --tag) RELEASE_TAG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer as root." >&2
  exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "This backup contains x86_64 binaries; target architecture must be x86_64." >&2
  exit 1
fi

if [[ -z "$TARGET_IP" ]]; then
  read -r -p "Target server public IPv4: " TARGET_IP </dev/tty
fi
if [[ ! "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Invalid IPv4 address: $TARGET_IP" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y gh age zstd rsync curl ca-certificates python3 ufw

if ! id cooper >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash cooper
fi
install -d -o cooper -g cooper -m 0755 /home/cooper

if [[ -z "${GH_TOKEN:-}" ]]; then
  read -r -s -p "GitHub token (private repo Contents: read): " GH_TOKEN </dev/tty
  echo
  export GH_TOKEN
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"; unset GH_TOKEN' EXIT

if ! gh api "repos/$BACKUP_REPO" >/dev/null 2>&1; then
  cat >&2 <<EOF
Cannot access the private repository: $BACKUP_REPO
Create a fine-grained token owned by geedama, select only
server-clone-backup, and grant Repository permissions -> Contents: Read-only.
EOF
  exit 1
fi

if [[ -z "$RELEASE_TAG" ]]; then
  RELEASE_TAG="$(gh api "repos/$BACKUP_REPO/releases/latest" --jq .tag_name)"
fi

echo "Downloading release: $RELEASE_TAG"
gh release download "$RELEASE_TAG" \
  --repo "$BACKUP_REPO" \
  --dir "$work_dir" \
  --pattern 'codex-server-backup.tar.zst.age*'

(
  cd "$work_dir"
  sha256sum -c codex-server-backup.tar.zst.age.sha256
)

echo
echo "Enter the backup encryption passphrase."
mkdir -p "$work_dir/extracted"
age -d "$work_dir/codex-server-backup.tar.zst.age" \
  | zstd -d \
  | tar -xpf - -C "$work_dir/extracted"

/bin/bash "$(dirname "$0")/restore.sh" \
  --from "$work_dir/extracted" \
  --target-ip "$TARGET_IP"
