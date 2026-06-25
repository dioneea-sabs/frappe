#!/usr/bin/env bash
#
# Pull the image and (re)start the stack. Safe to re-run.
# First run? follow with ./create-site.sh.
#
set -euo pipefail
cd "$(dirname "$0")"

# Update frappe_docker if already cloned (dc.sh clones it on first use).
if [ -d frappe_docker/.git ]; then
  echo ">> Updating frappe_docker"
  git -C frappe_docker pull --ff-only || true
fi

echo ">> Pulling image"
./dc.sh pull

echo ">> Starting stack"
./dc.sh up -d

echo ">> Up. First run? create the sites:  ./create-site.sh"
echo ">> Sanity check apps in the image:"
echo "   docker run --rm ghcr.io/frappe/helpdesk:v1.22.1 ls apps   # expect: frappe helpdesk telephony"
