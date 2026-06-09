# CraftCMS clean Docker setup

A clean Docker stack for [CraftCMS](https://craftcms.com/), built primarily for
local development — it avoids the file-ownership headaches you get when
bind-mounting code into the official image. A production build target is also
included (see [Development vs Production](#development-vs-production)).

- **`craft`** — custom nginx + php-fpm image (`./craftcms-nginx`)
- **`db`** — PostgreSQL 16

The Craft project lives in **`./craftcms`** on the host. In **dev** (the default)
it is bind-mounted into the container at `/app`, so you can edit it directly in
IntelliJ IDEA (or any editor) while it runs; in **prod** the code is baked into
the image instead.

---

## Why a custom image instead of `craftcms/nginx`?

The official image is fine, but for this workflow it has two limitations:

| | `craftcms/nginx:8.2` | This image |
|---|---|---|
| PHP version | 8.2 (no newer tag) | **8.4** |
| APCu (cache extension) | **missing** | **included** |
| Runs as | `www-data` (uid/gid **82**) | `appuser` (uid/gid **1000**) |

The last row is the important one for local dev. The container processes run as
**uid/gid 1000** (your host user). That means:

- files you create on the **host** (IntelliJ) are writable by nginx/php-fpm inside the container, and
- files Craft creates **inside the container** are owned by your user on the host and editable without `sudo`.

No `chown` dance for new or modified files.

> The image is built on Ubuntu 24.04 + `ppa:ondrej/php`, with nginx, php-fpm and
> supervisor. It bundles these PHP extensions: `apcu, bcmath, curl, gd, iconv,
> intl, mbstring, mysqlnd, opcache, pgsql, redis, soap, xml, zip`, plus Composer.

---

## Requirements

- Docker Engine + Docker Compose v2 (`docker compose ...`)
- A host user with uid/gid `1000` (the default). If yours differs, see
  [Matching your host user](#matching-your-host-user).

---

## Quick start (development)

This is the default workflow. For production, see
[Development vs Production](#development-vs-production) below.

```bash
# 1. Create your env file (edit values if you like)
cp .env.example .env

# 2. Build the craft image (uses HOST_UID/HOST_GID + PHP_VERSION from .env)
docker compose build

# 3. Start the database + web containers
docker compose up -d

# 4. Install CraftCMS into the (empty) ./craftcms folder
docker compose run --rm craft composer create-project craftcms/craft .

# 5. Run Craft setup (generates .env + security key, creates the DB schema
#    and your admin account)
docker compose run --rm craft php craft setup
```

`php craft setup` walks you through the database connection and creates the
admin account. The DB connection is already wired through environment variables
(see [Configuration](#configuration)), so you can accept the suggested defaults
for the database and just provide the site name, URL, and your admin credentials.

Then open:

- Site: <http://localhost:8080>
- Control panel: <http://localhost:8080/admin>

---

## Development vs Production

The image is a **multi-stage build** with two targets, selected for you by which
compose file you use. **Dev is the default** — you never have to pass anything
extra for normal local work.

| | **Dev** (default) | **Production** |
|---|---|---|
| Compose file | `docker-compose.yml` | `docker-compose.prod.yml` |
| Build target | `dev` | `prod` |
| App code | bind-mounted `./craftcms` → `/app` (edit live) | **baked into the image** |
| Dependencies | full (`composer install`) | `composer install --no-dev --optimize-autoloader` |
| opcache | re-checks files each request (edits are instant) | timestamp checks **off** (faster) |
| `open_basedir` | off (convenient) | **on** (hardened) |
| DB port on host | published (`5432`) | not published |
| Secrets | placeholder defaults are fine | **required** (build/run refuses without them) |
| Database volume | `craftcms-clean_craft-pgdata` | separate: `craftcms-clean-prod_craft-pgdata` |

### Development (the default)

Just use plain `docker compose` — it reads `docker-compose.yml` and builds the
`dev` target automatically:

```bash
docker compose build
docker compose up -d
```

### Production

The prod image bakes `./craftcms` in, so **Craft must already be installed there**
(do the dev quick-start once, or install Craft however you like). You also need
real secrets.

```bash
# 1. Put the required secrets in .env:
#      - CRAFT_SECURITY_KEY : copy the value Craft wrote into craftcms/.env
#                             during `php craft setup`
#      - POSTGRES_PASSWORD  : a strong, unique password
#    (The prod stack refuses to start if either is missing.)

# 2. Build the production image (code baked in, --no-dev, hardened)
docker compose -f docker-compose.prod.yml build

# 3. Start it
docker compose -f docker-compose.prod.yml up -d
```

All other prod commands follow the same pattern — just keep the
`-f docker-compose.prod.yml` flag:

```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f craft
docker compose -f docker-compose.prod.yml down
```

> **Rebuild on code changes.** Because prod bakes the code in, any change to
> `./craftcms` requires a rebuild (`... -f docker-compose.prod.yml build`) to
> take effect — that's the point of an immutable image.

> **Separate databases.** Dev and prod use different named volumes, so they do
> **not** share data. The prod stack starts with an empty database; run
> `docker compose -f docker-compose.prod.yml run --rm craft php craft install`
> (or restore a backup) to initialize it.

> **This is a baseline, not a turnkey production deploy.** It still terminates
> plain HTTP on `:8080` — put it behind a TLS-terminating reverse proxy
> (Traefik / nginx / cloud load balancer), use a managed or backed-up database,
> and supply secrets via your orchestrator rather than `.env` for a real
> deployment.

---

## Day-to-day usage

```bash
docker compose up -d            # start the stack
docker compose down             # stop it (data is kept in the named volume)
docker compose ps               # status
docker compose logs -f craft    # tail web/php-fpm/nginx logs
docker compose logs -f db       # tail postgres logs

# Run Craft CLI / Composer commands inside the web container:
docker compose run --rm craft php craft <command>
docker compose run --rm craft composer require <package>

# Open a shell in the running web container:
docker compose exec craft bash
```

After changing anything in `craftcms-nginx/` (Dockerfile or `etc/` configs),
rebuild and recreate:

```bash
docker compose build craft
docker compose up -d
```

---

## Configuration

All knobs live in **`.env`** (copied from `.env.example`). Compose reads it
automatically.

| Variable | Default | Purpose |
|---|---|---|
| `PHP_VERSION` | `8.4` | PHP version installed in the image (build arg) |
| `HOST_UID` / `HOST_GID` | `1000` | User the container runs as — match your host user |
| `WEB_PORT` | `8080` | Host port for the site |
| `DB_PORT` | `5432` | Host port for PostgreSQL |
| `POSTGRES_DB` | `craftcms` | Database name |
| `POSTGRES_USER` | `craftcms` | Database user |
| `POSTGRES_PASSWORD` | `secret` | Database password (use a strong one for prod) |
| `CRAFT_SECURITY_KEY` | _(unset)_ | **Prod only** — required by `docker-compose.prod.yml`; copy it from `craftcms/.env` |
| `APP_UID` / `APP_GID` | `1000` | **Prod only** — uid/gid the prod image runs as |

The `craft` service passes the DB settings to Craft via `CRAFT_DB_*` environment
variables (driver `pgsql`, host `db`, port `5432`), so Craft connects to the
`db` service out of the box. Postgres data persists in the `craft-pgdata` named
volume.

### Matching your host user

If `id -u` / `id -g` aren't `1000`, set them in `.env` before building:

```bash
echo "HOST_UID=$(id -u)" >> .env
echo "HOST_GID=$(id -g)" >> .env
docker compose build craft
```

---

## Project layout

```
.
├── craftcms-nginx/             # the custom web image (multi-stage: dev + prod)
│   ├── Dockerfile
│   └── etc/
│       ├── nginx/nginx.conf            # site on :8080, root /app/web
│       ├── php-fpm/php-fpm.conf
│       ├── php.d/60-craftcms.ini       # PHP + opcache tuning (env-driven)
│       ├── php.d/90-production.ini     # prod-only hardening (open_basedir, …)
│       ├── supervisord.conf
│       └── supervisord.d/              # nginx + php-fpm programs
├── craftcms/                   # ← your Craft project (bind-mounted in dev, baked in prod)
├── docker-compose.yml          # dev stack (default)
├── docker-compose.prod.yml     # production stack
├── .dockerignore               # keeps the build context small
├── .env.example                # copy to .env
└── .gitignore
```

---

## Troubleshooting

**`Bind for ...:5432 failed: port is already allocated`**
Another Postgres is using host port 5432. Either stop it, or set a different
`DB_PORT` in `.env` (e.g. `DB_PORT=5433`) and `docker compose up -d` again.
Containers still talk to each other on `5432` internally — `DB_PORT` only
changes the **host** mapping.

**HTTP 404 on <http://localhost:8080> before installing Craft**
Expected — `/app/web` is empty until you run `composer create-project`. Once
Craft is installed, the site responds normally.

**Permission errors editing files**
Make sure `HOST_UID`/`HOST_GID` in `.env` match `id -u` / `id -g`, then rebuild
the image (`docker compose build craft`). The uid/gid is baked in at build time.

**Reset everything (including the database)**
```bash
docker compose down -v          # -v also removes the craft-pgdata volume
```
This wipes the DB. Your Craft code in `./craftcms` is untouched.
