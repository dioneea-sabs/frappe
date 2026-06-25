#!/usr/bin/env bash
#
# One-time: create BOTH Helpdesk sites in the running bench.
# Run after ./deploy.sh. Each site NAME = its public hostname (DNS-based
# multitenancy); each gets its OWN database, sharing only the container stack.
#
set -euo pipefail
cd "$(dirname "$0")"

# DB root password from .env unless overridden in the environment.
DB_ROOT_PASSWORD="${DB_PASSWORD:-$(grep -E '^DB_PASSWORD=' .env 2>/dev/null | cut -d= -f2-)}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-CHANGE_ME_admin_password}"

SITES=(
  "support.testable.org"
  "mindssupport.testable.org"
)

for SITE in "${SITES[@]}"; do
  echo ">> Creating site $SITE (installing telephony + helpdesk)"
  # telephony is a HARD dependency of helpdesk (helpdesk hooks.py:
  # required_apps = ["telephony"]) — install it first, then helpdesk.
  ./dc.sh exec -T backend \
    bench new-site "$SITE" \
      --no-mariadb-socket \
      --db-root-username root \
      --mariadb-root-password "$DB_ROOT_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --install-app telephony \
      --install-app helpdesk

  ./dc.sh exec -T backend bench --site "$SITE" set-config developer_mode 0
  ./dc.sh exec -T backend bench --site "$SITE" clear-cache
  echo ">> $SITE ready -> https://$SITE/helpdesk"
done

echo ">> Both sites created (admin / \$ADMIN_PASSWORD)."
