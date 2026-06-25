#!/usr/bin/env bash
#
# Thin `docker compose` wrapper for the Helpdesk stack.
# - Clones frappe_docker (the source of the compose files) on first use, so you
#   never juggle folders — everything lives under this one directory.
# - Runs ONE compose project ("helpdesk") = official image + mariadb + redis,
#   with the bench's nginx exposed on 127.0.0.1:8080 for Apache to proxy to.
#
# Usage: ./dc.sh up -d | ./dc.sh logs -f | ./dc.sh exec -T backend bash | ./dc.sh down
#
set -euo pipefail
cd "$(dirname "$0")"

FD_DIR="frappe_docker"
FD_REPO="https://github.com/frappe/frappe_docker"
FD_REF="${FD_REF:-main}"          # pin a tag/branch here for reproducibility

if [ ! -d "$FD_DIR/.git" ]; then
  echo ">> Cloning frappe_docker ($FD_REF) ..." >&2
  git clone --depth 1 --branch "$FD_REF" "$FD_REPO" "$FD_DIR"
fi

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Run:  cp .env.example .env   (then set DB_PASSWORD)" >&2
  exit 1
fi

exec docker compose -p helpdesk --env-file .env \
  -f "$FD_DIR/compose.yaml" \
  -f "$FD_DIR/overrides/compose.mariadb.yaml" \
  -f "$FD_DIR/overrides/compose.redis.yaml" \
  -f "$FD_DIR/overrides/compose.noproxy.yaml" \
  "$@"
