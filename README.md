# Self-hosted Frappe Helpdesk (Docker, multi-instance, Apache edge)

Production setup for **Frappe Helpdesk** that:

- runs as an **immutable Docker image** (apps baked at build time — the official
  `frappe_docker` production pattern, *not* the dev `bench start` demo),
- coexists with **other Frappe instances** on the same server,
- coexists with **Apache**, which keeps owning ports **80/443** as the public
  TLS edge and reverse-proxies to Frappe.

## Architecture

```
            Apache (:80/:443, TLS via certbot)        <-- public edge you already run
              |  helpdesk.example.com  -> 127.0.0.1:8080  (preserve Host)
              |  other.example.com     -> 127.0.0.1:8080
              |  your-existing-sites   -> served by Apache directly
              v
        Traefik router (127.0.0.1:8080, localhost only)   <-- internal, no TLS
              |  Host(helpdesk.example.com) -> helpdesk bench
              |  Host(other.example.com)    -> other bench
              v
   [ helpdesk bench ]  [ other bench ]  ...   each: nginx + gunicorn + socketio
              \              /                       + workers + scheduler + redis
               \            /
            shared MariaDB (mariadb-database, one DB engine for all benches)
```

Each Frappe instance is its own Docker Compose **project**; adding one never
touches Apache's ports. Traefik is the single internal router so you don't
juggle a unique port per bench.

| Component   | Version            |
|-------------|--------------------|
| Frappe      | `version-16`       |
| Helpdesk    | `main`             |
| Telephony   | `develop` (helpdesk dependency) |

## Files in this directory

| File | Purpose |
|------|---------|
| `apps.json` | Apps baked into the image (frappe comes from build args). |
| `build.sh` | Build the custom `helpdesk:v16` image. |
| `deploy.sh` | Bring up MariaDB + Traefik + helpdesk bench. |
| `create-site.sh` | One-time site creation + app install. |
| `gitops/mariadb.env` | Shared DB root password. |
| `gitops/traefik.env` | Internal router (localhost:8080) + dashboard auth. |
| `gitops/helpdesk.env` | This bench's image, DB, hostname, routing. |
| `apache/helpdesk.conf` | Apache vhost: TLS + reverse proxy + **websockets**. |

> Replace every `CHANGE_ME...` and `*.example.com` before deploying.

---

## Deploy (on the server)

### 0. Prereqs
Docker + Docker Compose v2, Apache with `mod_proxy mod_proxy_http
mod_proxy_wstunnel mod_ssl mod_rewrite mod_headers`, and DNS A-records for your
hostnames pointing at the server.

### 1. Get frappe_docker and this config
```bash
git clone https://github.com/frappe/frappe_docker
cd frappe_docker
# put this directory's files alongside it, e.g.:
#   frappe_docker/        (the clone)
#   gitops/  apps.json  build.sh  deploy.sh  create-site.sh  apache/
cp /path/to/this/apps.json .
```

### 2. Build the image
```bash
./build.sh          # = frappe version-16 + helpdesk main + telephony develop
```
Updating later = re-run `build.sh` (it pulls fresh app code), then redeploy +
`bench migrate` (see below).

### 3. Fill in secrets
Edit `gitops/mariadb.env`, `gitops/traefik.env`, `gitops/helpdesk.env`
(DB password must match in mariadb.env and helpdesk.env). For Traefik dashboard
auth: `htpasswd -nbB admin 'pw'` then double every `$` in the hash.

### 4. Start the stack
```bash
./deploy.sh
```

### 5. Create the site (first run only)
```bash
SITE=helpdesk.example.com \
ADMIN_PASSWORD='set-a-strong-one' \
DB_ROOT_PASSWORD='same-as-mariadb.env' \
./create-site.sh
```

### 6. Wire up Apache
```bash
# Debian/Ubuntu
sudo a2enmod proxy proxy_http proxy_wstunnel ssl rewrite headers
sudo cp apache/helpdesk.conf /etc/apache2/sites-available/helpdesk.conf
sudo certbot certonly --webroot -w /var/www/html -d helpdesk.example.com
sudo a2ensite helpdesk && sudo apachectl configtest && sudo systemctl reload apache2
```
Open `https://helpdesk.example.com/helpdesk`  (login `admin` / your password).

---

## Add another Frappe instance

1. Build its image (own `apps.json` if different apps) → `otherapp:v16`.
2. `cp gitops/helpdesk.env gitops/other.env`, then set `ROUTER=other`,
   `SITES_RULE=Host(`other.example.com`)`,
   `FRAPPE_SITE_NAME_HEADER=other.example.com`, `CUSTOM_IMAGE=otherapp`.
3. `docker compose -p other --env-file gitops/other.env -f compose.yaml \
     -f overrides/compose.redis.yaml -f overrides/compose.multi-bench.yaml up -d`
4. Create its site (as in step 5).
5. Copy `apache/helpdesk.conf` → change `ServerName` + cert paths (upstream
   stays `127.0.0.1:8080`), certbot, reload Apache.

MariaDB and Traefik are shared — you do **not** start them again.

---

## Update / upgrade

```bash
./build.sh                                   # rebuild image with latest app code
docker compose -p helpdesk --env-file gitops/helpdesk.env \
  -f compose.yaml -f overrides/compose.redis.yaml \
  -f overrides/compose.multi-bench.yaml up -d   # recreate with new image
docker compose -p helpdesk exec backend \
  bench --site helpdesk.example.com migrate    # run DB migrations
```
Pin to releases (not moving branches) for reproducibility: set
`FRAPPE_BRANCH=v16.x.y` and a tag in `apps.json` when you want immutable builds.

## Backups
```bash
docker compose -p helpdesk exec backend \
  bench --site helpdesk.example.com backup --with-files
```
Files land in the `sites` volume (`.../sites/helpdesk.example.com/private/backups`).
For scheduled backups use `overrides/compose.backup-cron.yaml`, and back up the
MariaDB `db-data` volume + the `sites` volume off-box.

## Why this shape (design notes)
- **Immutable image, not `bench get-app` at runtime** — production images are
  built once with assets pre-compiled; you can't change app code in a running
  container. This is what makes upgrades a clean rebuild+migrate.
- **One shared MariaDB / one shared Traefik** — the documented single-server
  multi-bench pattern. Each bench keeps its own Redis + workers (isolation)
  while sharing the DB engine and the router.
- **Apache as edge, Traefik on localhost** — Traefik binds `127.0.0.1:8080`
  only, so it's unreachable externally; Apache owns TLS and 80/443 exactly as
  today. `ProxyPreserveHost On` lets Traefik route by hostname;
  `mod_proxy_wstunnel` carries Frappe's socket.io websockets.

## Sources
- frappe_docker — https://github.com/frappe/frappe_docker
- Build custom image — https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/02-build-setup.md
- Single-server (Traefik) — https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/07-single-server-example.md
- Multi-tenancy — https://github.com/frappe/frappe_docker/blob/main/docs/03-production/03-multi-tenancy.md
- Compose overrides — https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/05-overrides.md
- Helpdesk — https://github.com/frappe/helpdesk
