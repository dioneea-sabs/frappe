#!/usr/bin/env bash
#
# One-time: create BOTH Helpdesk sites inside the running bench.
# Each site NAME must equal its public hostname (DNS-based multitenancy).
# Each site gets its OWN database; they only share the container stack.
#
set -euo pipefail

ADMIN_PASSWORD="${ADMIN_PASSWORD:-CHANGE_ME_admin_password}"
# Must match gitops/mariadb.env DB_PASSWORD:
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-CHANGE_ME_strong_db_root_password}"

SITES=(
  "support.testable.org"
  "mindssupport.testable.org"
)

for SITE in "${SITES[@]}"; do
  echo ">> Creating site $SITE (installing telephony + helpdesk)"
  # telephony is a HARD dependency of helpdesk (helpdesk hooks.py:
  # required_apps = ["telephony"]) — install it first, then helpdesk.
  docker compose --project-name helpdesk exec backend \
    bench new-site "$SITE" \
      --no-mariadb-socket \
      --db-root-username root \
      --mariadb-root-password "$DB_ROOT_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --install-app telephony \
      --install-app helpdesk

  docker compose --project-name helpdesk exec backend \
    bench --site "$SITE" set-config developer_mode 0
  docker compose --project-name helpdesk exec backend \
    bench --site "$SITE" clear-cache
  echo ">> $SITE ready -> https://$SITE/helpdesk"
done

echo ">> Both sites created (admin / \$ADMIN_PASSWORD)."
