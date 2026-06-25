#!/usr/bin/env bash
#
# One-time: create the Helpdesk site inside the running bench and install apps.
# The site NAME must equal the public hostname (DNS-based multitenancy +
# FRAPPE_SITE_NAME_HEADER).
#
set -euo pipefail

SITE="${SITE:-helpdesk.example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-CHANGE_ME_admin_password}"
# Must match gitops/mariadb.env DB_PASSWORD:
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-CHANGE_ME_strong_db_root_password}"

echo ">> Creating site $SITE (installing telephony + helpdesk)"
docker compose --project-name helpdesk exec backend \
  bench new-site "$SITE" \
    --no-mariadb-socket \
    --db-root-username root \
    --mariadb-root-password "$DB_ROOT_PASSWORD" \
    --admin-password "$ADMIN_PASSWORD" \
    --install-app telephony \
    --install-app helpdesk

# Production hygiene (the demo init.sh enables developer_mode/mute_emails — we
# do NOT want those in production).
docker compose --project-name helpdesk exec backend \
  bench --site "$SITE" set-config developer_mode 0
docker compose --project-name helpdesk exec backend \
  bench --site "$SITE" clear-cache

echo ">> Done. Helpdesk UI will be at https://$SITE/helpdesk  (admin / \$ADMIN_PASSWORD)"
