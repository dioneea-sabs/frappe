#!/usr/bin/env bash
#
# Pull the latest image (and frappe_docker compose files) and (re)start the
# stack. Safe to re-run for upgrades. First run? follow with ./create-site.sh.
#
set -euo pipefail
cd "$(dirname "$0")"

# Update frappe_docker if it's already cloned (dc.sh clones it on first use).
if [ -d frappe_docker/.git ]; then
  echo ">> Updating frappe_docker"
  git -C frappe_docker pull --ff-only || true
fi

echo ">> Pulling image"
./dc.sh pull

echo ">> Starting stack"
./dc.sh up -d

echo ">> Up. First run? create the sites:  ./create-site.sh"
