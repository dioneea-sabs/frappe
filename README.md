# Self-hosted Frappe Helpdesk (Docker, two sites, Apache edge)

Production setup for **Frappe Helpdesk** serving two sites:

- `support.testable.org`
- `mindssupport.testable.org`

Both run on **one bench** (one container stack) but have **fully separate
databases**, resolved by hostname (Frappe DNS-based multitenancy). It:

- runs the **official prebuilt image** `ghcr.io/frappe/helpdesk` (immutable, apps
  + assets baked in — the `frappe_docker` production pattern, *not* the dev
  `bench start` demo); nothing to build or maintain,
- coexists with future **other Frappe instances** on the same server,
- coexists with **Apache**, which keeps owning ports **80/443** as the public
  TLS edge and reverse-proxies to Frappe.

## Architecture

```
            Apache (:80/:443, TLS via certbot)        <-- public edge you already run
              |  support.testable.org       -> 127.0.0.1:8080  (Host preserved)
              |  mindssupport.testable.org  -> 127.0.0.1:8080  (Host preserved)
              |  your-existing-sites        -> served by Apache directly
              v
        Traefik router (127.0.0.1:8080, localhost only)   <-- internal, no TLS
              |  Host(support.testable.org) || Host(mindssupport...) -> helpdesk bench
              v
        [ helpdesk bench ]  nginx + gunicorn + socketio + workers + scheduler + redis
              |  site resolved from Host header:
              |     support.testable.org      -> its own DB
              |     mindssupport.testable.org  -> its own DB
              v
        shared MariaDB (mariadb-database)   <-- one DB engine, two databases
```

```mermaid
flowchart TD
    net([Internet])

    subgraph edge["Apache — public edge (:80 / :443, TLS via certbot)"]
        v1["vhost: support.testable.org"]
        v2["vhost: mindssupport.testable.org"]
        v3["vhosts: your existing Apache sites"]
    end

    traefik["Traefik router<br/>127.0.0.1:8080 (localhost only, no TLS)<br/>routes by Host header"]

    subgraph bench["Helpdesk bench — one container stack"]
        fe["nginx frontend<br/>resolves site from Host"]
        gunicorn["gunicorn (backend)"]
        socketio["socketio (websockets)"]
        workers["workers + scheduler"]
        redis[("redis cache + queue")]
    end

    subgraph db["shared MariaDB (mariadb-database)"]
        db1[("DB: support.testable.org")]
        db2[("DB: mindssupport.testable.org")]
    end

    served["served directly by Apache"]

    net --> edge
    v1 -- "preserve Host + ws tunnel" --> traefik
    v2 -- "preserve Host + ws tunnel" --> traefik
    v3 --> served
    traefik --> fe
    fe --> gunicorn
    fe --> socketio
    gunicorn --> workers
    fe -. uses .-> redis
    gunicorn -- "Host = support.testable.org" --> db1
    gunicorn -- "Host = mindssupport.testable.org" --> db2
```

Why Traefik when Apache is already the edge? It's the single internal entry
point: every Apache vhost proxies to the same `127.0.0.1:8080` and Traefik
routes by hostname. When you add the *other* Frappe instances later, Apache
needs no new ports — just another vhost.

| Component   | Version            |
|-------------|--------------------|
| Frappe      | `version-15` (from the official image) |
| Helpdesk    | pinned release, e.g. `v1.26.2` (`main` line) |
| Telephony   | `develop`          |
| Image       | `ghcr.io/frappe/helpdesk` (official, prebuilt) |

**Why telephony?** It is a hard dependency of Helpdesk — `helpdesk/hooks.py`
declares `required_apps = ["telephony"]` and `pyproject.toml` pins
`telephony >=0.0.1,<1.0.0`. Frappe refuses to install `helpdesk` without it.
It's installed automatically; ignore its UI if you don't use call features.

## Files in this directory

| File | Purpose |
|------|---------|
| `deploy.sh` | Bring up MariaDB + Traefik + the helpdesk bench. |
| `create-site.sh` | One-time: create **both** sites + install apps. |
| `gitops/mariadb.env` | Shared DB root password. |
| `gitops/traefik.env` | Internal router (localhost:8080) + dashboard auth. |
| `gitops/helpdesk.env` | Bench image, DB, and the two hostnames it serves. |
| `apache/support.testable.org.conf` | Apache vhost: TLS + proxy + websockets. |
| `apache/mindssupport.testable.org.conf` | Second site's vhost. |

> Replace every `CHANGE_ME...` before deploying.

---

## The image (official, prebuilt — no build needed)

Frappe publishes a ready-to-use **production** image at
**`ghcr.io/frappe/helpdesk`** — its CI builds `frappe version-15 + helpdesk +
telephony` (assets pre-compiled) from the same `frappe_docker` Containerfile you
would otherwise run yourself. It's a **public** package, so there's no build
pipeline, no registry auth, nothing to maintain — the server just pulls it.

- `gitops/helpdesk.env` already points at `ghcr.io/frappe/helpdesk`.
- Pin a release tag (e.g. `CUSTOM_TAG=v1.26.2`) for reproducibility; `stable` is
  the latest `main` build. Tags: <https://github.com/frappe/helpdesk/pkgs/container/helpdesk>
- Multi-arch (amd64 + arm64), so it runs on Intel and ARM hosts alike.

> Trade-off: the official image tracks Frappe **version-15** (the line Helpdesk
> is tested against). If you ever need version-16 or extra apps in the image,
> you'd switch to a self-built image — but for plain Helpdesk this is the
> simplest, most maintainable path.

## Deploy (on the server)

### 0. Prereqs
Docker + Docker Compose v2; Apache with `mod_proxy mod_proxy_http
mod_proxy_wstunnel mod_ssl mod_rewrite mod_headers`; DNS A-records for both
hostnames pointing at the server.

### 1. Get frappe_docker and this config
```bash
git clone https://github.com/frappe/frappe_docker
cd frappe_docker
# keep gitops/ deploy.sh create-site.sh apache/ next to the clone.
# (frappe_docker is needed for its compose.yaml + overrides, NOT for building.)
```

### 2. Fill in secrets
Edit `gitops/mariadb.env`, `gitops/traefik.env`, `gitops/helpdesk.env`
(the DB password must match in mariadb.env and helpdesk.env). Traefik dashboard
auth: `htpasswd -nbB admin 'pw'`, then double every `$` in the hash.

### 3. Start the stack
```bash
./deploy.sh          # pulls ghcr.io/frappe/helpdesk automatically (PULL_POLICY=always)
```

### 4. Create both sites (first run only)
```bash
ADMIN_PASSWORD='set-a-strong-one' \
DB_ROOT_PASSWORD='same-as-mariadb.env' \
./create-site.sh
```

### 5. Wire up Apache (both domains)
```bash
sudo a2enmod proxy proxy_http proxy_wstunnel ssl rewrite headers      # Debian/Ubuntu
sudo cp apache/support.testable.org.conf      /etc/apache2/sites-available/
sudo cp apache/mindssupport.testable.org.conf /etc/apache2/sites-available/
sudo certbot certonly --webroot -w /var/www/html -d support.testable.org
sudo certbot certonly --webroot -w /var/www/html -d mindssupport.testable.org
sudo a2ensite support.testable.org mindssupport.testable.org
sudo apachectl configtest && sudo systemctl reload apache2
```
Open `https://support.testable.org/helpdesk` and
`https://mindssupport.testable.org/helpdesk` (login `admin` / your password).

---

## Day-2 operations

### Update / upgrade (covers BOTH sites)
Bump `CUSTOM_TAG` in `gitops/helpdesk.env` to the new release (check the
[tags](https://github.com/frappe/helpdesk/pkgs/container/helpdesk)), then pull +
recreate + migrate:
```bash
docker compose -p helpdesk --env-file gitops/helpdesk.env \
  -f compose.yaml -f overrides/compose.redis.yaml \
  -f overrides/compose.multi-bench.yaml pull        # fetch new image from GHCR
docker compose -p helpdesk --env-file gitops/helpdesk.env \
  -f compose.yaml -f overrides/compose.redis.yaml \
  -f overrides/compose.multi-bench.yaml up -d        # recreate with new image
docker compose -p helpdesk exec backend bench --site support.testable.org      migrate
docker compose -p helpdesk exec backend bench --site mindssupport.testable.org migrate
```
Pinning a release tag (not `stable`) keeps rollouts reproducible and lets you
roll back by setting `CUSTOM_TAG` to the previous version.

### Backups (per site — each has its own DB)
```bash
docker compose -p helpdesk exec backend bench --site support.testable.org      backup --with-files
docker compose -p helpdesk exec backend bench --site mindssupport.testable.org backup --with-files
```
Back up the MariaDB `db-data` volume and the bench `sites` volume off-box.
For scheduled backups, add `overrides/compose.backup-cron.yaml`.

### Add a third Helpdesk site later (same bench)
Append the hostname to `SITES_RULE` in `gitops/helpdesk.env`, `up -d` again,
create the site, add an Apache vhost. No new containers.

### Add a *different* Frappe app instance later (separate bench)
Point its env at that app's image — another official one (e.g. `frappe/crm` on
GHCR) or a self-built image if no official one exists — then a new env file with
a different `ROUTER` and `SITES_RULE`, run the helpdesk-style stack as a new
project, and add an Apache vhost (still upstream `127.0.0.1:8080` — Traefik
routes it). MariaDB and Traefik are already shared; don't restart them.

## Persistence: where files and databases live

Nothing important lives *inside* a container — the immutable images are
disposable. All state is in **Docker named volumes**, so rebuilds/upgrades never
lose data.

### Uploaded files (filesystem)
Frappe stores attachments on disk, not in the DB (the DB only holds a `File`
metadata row). Both sites share one `sites` volume; isolation is by directory:

```
sites/                                 (volume: helpdesk_sites)
├── support.testable.org/
│   ├── public/files/     ← public attachments (nginx serves directly)
│   ├── private/files/    ← private attachments (permission-checked)
│   └── site_config.json  ← per-site DB name + DB password + ENCRYPTION KEY
├── mindssupport.testable.org/
│   ├── public/files/
│   ├── private/files/
│   └── site_config.json
└── common_site_config.json
```

### Databases (one server, one DB per site)
There is **one** MariaDB server (one data volume), and **each site gets its own
separate database** inside it — created by `bench new-site` with an
auto-generated name (e.g. `_a1b2c3…`). The site's DB name, DB user, and DB
password are recorded in that site's `site_config.json`. So data isolation is at
the *database* level, even though both DBs share the same storage volume.

```
MariaDB server (container mariadb-database)   →  volume: mariadb_db-data  (/var/lib/mysql)
   ├── database for support.testable.org       (own name/user/password)
   └── database for mindssupport.testable.org  (own name/user/password)
```

### Volume map
| Host volume | Project | Mounted at | Holds |
|-------------|---------|-----------|-------|
| `helpdesk_sites` | helpdesk | `/home/frappe/frappe-bench/sites` | uploads (public/private), each site's `site_config.json` (incl. **encryption key**), backups |
| `mariadb_db-data` | mariadb | `/var/lib/mysql` | **all** site databases (one per site) |
| `helpdesk_redis-queue-data` | helpdesk | `/data` | queued background jobs (redis-queue) |
| *(redis-cache)* | helpdesk | — | none — cache is ephemeral by design |

> 💾 **Back up both `helpdesk_sites` and `mariadb_db-data` off-box.** DB without
> the matching `sites/<site>/site_config.json` is useless — the encryption key
> there is what decrypts stored secrets. `bench backup --with-files` bundles
> DB+files per site (lands in `sites/<site>/private/backups/`); copy that, or the
> two volumes, somewhere off the server.

> ⚠️ Inspect volumes with `docker volume ls` / `docker volume inspect <name>`.
> Removing a volume (`docker volume rm`, `docker compose down -v`) **deletes the
> data permanently** — `down -v` on the helpdesk or mariadb project wipes files
> or databases. Use plain `down` (no `-v`) for routine stop/recreate.

## Coexistence on the shared host (port map)

This stack is built to sit next to existing services (Apache, and — as you
noted — an existing host **MySQL** and/or **Redis**). The rule: **nothing in the
Frappe stack publishes a public host port.** The only host binding is Apache's
(already yours) plus a single loopback-only port for the internal router.

| Host port | Bound by this stack? | Used by | Conflict with your existing service? |
|-----------|----------------------|---------|--------------------------------------|
| `80` / `443` | No (Apache already owns them) | your Apache edge | — none; Frappe never binds these |
| `127.0.0.1:8080` | **Yes — loopback only** | internal Traefik router | none; not your existing MySQL/Redis/Apache |
| `3306` (MySQL) | **No** | container MariaDB, internal `mariadb-network` only | **none** — your host MySQL keeps `:3306` |
| `6379` (Redis) | **No** | container redis-cache + redis-queue, internal to the bench network | **none** — your host Redis keeps `:6379` |

Why there's no clash with your existing **MySQL** and **Redis**: the
`compose.mariadb-shared.yaml` and `compose.redis.yaml` overrides declare **no
`ports:` mappings**, so those containers are reachable only on Docker networks
(`mariadb-database:3306`, `redis-cache:6379`, `redis-queue:6379`) — never on the
host's `0.0.0.0`. Each Frappe bench also runs its **own** Redis pair, fully
separate from whatever your host Redis is doing (no shared keyspace, no
`SELECT db` collisions).

> ⚠️ The only way to create a conflict is to add a `ports:` line that publishes
> 3306 or 6379 (or to set `network_mode: host`) on the DB/Redis/Traefik
> services. Don't. If you need host access for debugging, publish on a *spare*
> port, e.g. `"3307:3306"` / `"6380:6379"`.

Reuse-the-host-service is possible but **not recommended**: Frappe officially
targets **MariaDB** (MySQL 8 has `utf8mb4`/collation quirks), and a shared Redis
couples Frappe's cache/queue lifecycle to your other apps. Keeping dedicated,
internal containers is the maintained best practice and what these files do.

## Design notes
- **Immutable image, not `bench get-app` at runtime** — production images ship
  with assets pre-compiled; you can't change app code in a running container.
  Upgrades = rebuild + migrate.
- **One bench, two sites** — both Helpdesks share compute but have isolated
  databases; one image rebuild upgrades both. (Choose separate benches only if
  you need independent upgrade windows or resource isolation.)
- **Apache edge, Traefik on localhost** — Traefik binds `127.0.0.1:8080` only,
  so it's unreachable externally; Apache keeps TLS and 80/443.
  `ProxyPreserveHost On` drives hostname routing; `mod_proxy_wstunnel` carries
  Frappe's socket.io websockets (required for realtime/notifications).

## Sources
- frappe_docker — https://github.com/frappe/frappe_docker
- Build custom image — https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/02-build-setup.md
- Single-server (Traefik) — https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/07-single-server-example.md
- Multi-tenancy — https://github.com/frappe/frappe_docker/blob/main/docs/03-production/03-multi-tenancy.md
- Compose overrides — https://github.com/frappe/frappe_docker/blob/main/docs/02-setup/05-overrides.md
- Helpdesk (telephony dependency in hooks.py) — https://github.com/frappe/helpdesk
