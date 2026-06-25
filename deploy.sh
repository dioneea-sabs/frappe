#!/usr/bin/env bash
#
# Bring up / update the full stack:
#   1. shared MariaDB      (project: mariadb,  network: mariadb-network)
#   2. internal Traefik    (project: traefik,  network: traefik-public, 127.0.0.1:8080)
#   3. helpdesk bench      (project: helpdesk, uses both networks above)
#
# Run from inside a frappe_docker clone. gitops/ env files are referenced by
# the GITOPS path below (default: ../gitops relative to frappe_docker).
#
set -euo pipefail

FRAPPE_DOCKER="${FRAPPE_DOCKER:-$PWD}"
GITOPS="${GITOPS:-$(cd "$FRAPPE_DOCKER/.." && pwd)/gitops}"

if [ ! -f "$FRAPPE_DOCKER/compose.yaml" ]; then
  echo "ERROR: \$FRAPPE_DOCKER ($FRAPPE_DOCKER) is not a frappe_docker clone." >&2
  exit 1
fi
cd "$FRAPPE_DOCKER"

echo ">> [1/3] shared MariaDB"
docker compose --project-name mariadb \
  --env-file "$GITOPS/mariadb.env" \
  -f overrides/compose.mariadb-shared.yaml \
  up -d

echo ">> [2/3] internal Traefik router (127.0.0.1:8080)"
docker compose --project-name traefik \
  --env-file "$GITOPS/traefik.env" \
  -f overrides/compose.traefik.yaml \
  up -d

echo ">> [3/3] helpdesk bench"
# compose.yaml            -> backend/frontend/websocket/workers/scheduler
# compose.redis.yaml      -> per-bench redis-cache + redis-queue
# compose.multi-bench.yaml-> joins shared traefik-public + mariadb-network,
#                            registers Traefik host-routing labels
docker compose --project-name helpdesk \
  --env-file "$GITOPS/helpdesk.env" \
  -f compose.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.multi-bench.yaml \
  up -d

echo
echo ">> Stack is up. If this is the FIRST run, create the site now:"
echo "   ./create-site.sh"
echo ">> To UPDATE after rebuilding the image:"
echo "   docker compose -p helpdesk exec backend bench --site helpdesk.example.com migrate"
