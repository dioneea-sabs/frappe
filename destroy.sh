#!/usr/bin/env bash
#
# ☢️  DANGER — PERMANENTLY ERASES the Helpdesk deployment:
#       - all its containers (backend, db, redis, nginx, workers, scheduler)
#       - its networks
#       - its named volumes:
#           helpdesk_sites            uploaded FILES + site_config (ENCRYPTION KEYS)
#           helpdesk_db-data          BOTH sites' DATABASES
#           helpdesk_redis-queue-data queued jobs
#     This cannot be undone. Back up first if you might want the data.
#
# SCOPE: strictly the `helpdesk` compose project. It does NOT touch your other
# Docker stacks, the host MySQL/Redis, or Apache.
#
# Usage:  ./destroy.sh           (asks for confirmation)
#         FORCE=1 ./destroy.sh   (no prompt — for automation)
#         WIPE_FRAPPE_DOCKER=1 ./destroy.sh   (also delete the ./frappe_docker clone)
#
set -euo pipefail
cd "$(dirname "$0")"

PROJECT="helpdesk"
VOLUMES=(helpdesk_sites helpdesk_db-data helpdesk_redis-queue-data)

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found." >&2; exit 1
fi

cat <<EOF
############################################################################
☢️  This will PERMANENTLY DELETE the "$PROJECT" stack and ALL its data:
      containers + networks + volumes
      -> ${VOLUMES[*]}
    (both sites' databases AND all uploaded files — irreversible)

    Other Docker stacks, host MySQL/Redis, and Apache are NOT affected.
############################################################################
EOF

if [ "${FORCE:-0}" != "1" ]; then
  read -r -p 'Type EXACTLY  erase helpdesk  to proceed: ' answer
  [ "$answer" = "erase helpdesk" ] || { echo "Aborted — nothing deleted."; exit 1; }
fi

echo ">> Removing containers (project=$PROJECT)"
cids=$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" || true)
[ -n "$cids" ] && docker rm -f $cids || echo "   (none)"

echo ">> Removing named volumes"
# explicit names first, then anything else labeled to the project
docker volume rm -f "${VOLUMES[@]}" 2>/dev/null || true
vids=$(docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT" || true)
[ -n "$vids" ] && docker volume rm -f $vids || true

echo ">> Removing networks"
nids=$(docker network ls -q --filter "label=com.docker.compose.project=$PROJECT" || true)
[ -n "$nids" ] && docker network rm $nids 2>/dev/null || echo "   (none)"

if [ "${WIPE_FRAPPE_DOCKER:-0}" = "1" ] && [ -d frappe_docker ]; then
  echo ">> Removing ./frappe_docker clone"
  rm -rf frappe_docker
fi

echo ">> Done. The '$PROJECT' stack and its data are gone."
echo "   Your other Docker stacks, host MySQL/Redis, and Apache were untouched."
echo "   To redeploy from scratch:  ./deploy.sh  &&  ./create-site.sh"
