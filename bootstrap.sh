#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="https://raw.githubusercontent.com/geedama/server-clone/main"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y curl ca-certificates
fi

curl -fsSL "$BASE_URL/install.sh" -o "$work_dir/install.sh"
curl -fsSL "$BASE_URL/restore.sh" -o "$work_dir/restore.sh"
chmod 755 "$work_dir/install.sh" "$work_dir/restore.sh"

/bin/bash "$work_dir/install.sh" "$@"
