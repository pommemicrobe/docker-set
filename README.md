# Docker-Set

Docker environment for managing multiple web applications with shared infrastructure (Traefik + MySQL).

## Project Structure

```
docker-set/
├── config/                   # Infrastructure configuration
│   ├── traefik/              # Reverse proxy + SSL
│   ├── mysql/                # Shared database
│   └── default-site.dist/    # Templates for the default site (IP access)
├── lib/                      # Shared bash libraries
│   ├── common.sh             # Colors, logging, validation, utilities
│   ├── site.sh               # Site creation, aliases, manifest, versions
│   ├── database.sh           # MySQL operations, credential injection
│   └── framework.sh          # Framework installation
├── scripts/                  # Management scripts
│   ├── setup.sh              # Initial setup wizard
│   ├── site-create.sh        # Create a site (+ DB, + framework, + git source)
│   ├── site-update.sh        # Update a site (rebuild, version, resources, mode)
│   ├── site-deploy.sh        # Deploy a site (git pull + rebuild/restart)
│   ├── site-shell.sh         # Interactive shell inside a site's container
│   ├── site-run.sh           # One-off command inside a site's container
│   ├── site-delete.sh        # Delete a site
│   ├── site-list.sh          # List sites and their status
│   ├── site-backup.sh        # Backup site files + DB
│   ├── site-restore.sh       # Restore from a backup
│   └── default-site.sh       # Configure default response for IP access
├── templates/                # Site templates
│   ├── dockerfiles/          # Shared multi-stage Dockerfiles (one per runtime)
│   ├── php-traefik/          # compose.yaml + compose.prod.yaml + .env.dist
│   ├── php-standalone/
│   ├── nodejs-traefik/
│   ├── nodejs-standalone/
│   ├── bun-traefik/
│   ├── bun-standalone/
│   ├── go-traefik/
│   └── go-standalone/
├── frameworks/               # Framework installers
│   ├── laravel/              # PHP
│   ├── wordpress/            # PHP
│   ├── nextjs/               # Node.js
│   ├── elysia/               # Bun
│   └── gin/                  # Go
├── sites/                    # Deployed sites (each has site.yaml manifest)
├── backups/                  # Site backups (.tar.gz)
└── tests/                    # Smoke tests
```

---

## Quick Start

```bash
# 1. Clone the project
git clone <repo> && cd docker-set

# 2. Run setup (configures Traefik + MySQL)
./scripts/setup.sh

# 3. Create your first site
./scripts/site-create.sh my-site my-site.com php-traefik
```

---

## Initial Setup

### Prerequisites

- Docker Engine and Docker Compose v2
- Sudo access (Docker commands typically require root)

### Automated Setup

```bash
./scripts/setup.sh
```

The wizard configures:
- Docker network `web`
- Traefik (reverse proxy + Let's Encrypt SSL)
- MySQL (shared database for all sites)

You'll be prompted for:
1. **Email** for Let's Encrypt
2. **MySQL root password** (auto-generated if omitted)

---

## Site Management

### Create a Site

```bash
./scripts/site-create.sh [name] [url] [template] [options]
```

Run without arguments for interactive mode. Otherwise:

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--cpu <num>` | CPU limit | `1` |
| `--memory <size>` | Memory limit (e.g. `512M`, `1G`) | `512M` |
| `--php-version <ver>` | PHP version: 8.2, 8.3, 8.4, 8.5 | `8.5` |
| `--node-version <ver>` | Node.js version: 22, 24 | `24` |
| `--bun-version <ver>` | Bun version: 1, 1.3 | `1.3` |
| `--go-version <ver>` | Go version: 1.25, 1.26 | `1.26` |
| `--mode <dev\|prod>` | dev: live code mount; prod: code baked into the image (see [Site Modes](#site-modes)) | `dev` |
| `--framework <name>` | Install a framework (see below) | — |
| `--from-git <url>` | Clone a git repo into `app/` (mutually exclusive with `--framework`) | — |
| `--branch <name>` | Branch to clone (requires `--from-git`) | repo default |
| `--with-db` | Create a MySQL database and user | off |
| `--no-ssl` | Use HTTP instead of HTTPS (local dev) | off |
| `--no-autostart` | Don't auto-start container when Docker starts | off |
| `--no-start` | Don't start container after creation | off |
| `--aliases <domains>` | Extra domains, comma-separated | — |
| `--redirect-aliases` | 301-redirect aliases to the main URL | off |

**Examples:**

```bash
# PHP + Laravel + MySQL
./scripts/site-create.sh my-blog my-blog.com php-traefik --framework laravel --with-db

# WordPress
./scripts/site-create.sh shop shop.com php-traefik --framework wordpress --with-db

# Node.js API with Next.js
./scripts/site-create.sh api api.example.com nodejs-traefik --framework nextjs

# Bun API with Elysia
./scripts/site-create.sh elysia-api api.example.com bun-traefik --framework elysia

# Go API with Gin
./scripts/site-create.sh go-api api.example.com go-traefik --framework gin --with-db

# Production mode (immutable image, code baked in)
./scripts/site-create.sh api api.example.com go-traefik --mode prod

# Production site deployed from a git repository
./scripts/site-create.sh app app.example.com nodejs-traefik --mode prod \
  --from-git https://github.com/me/app.git --branch main

# Local dev without SSL
./scripts/site-create.sh dev dev.local php-traefik --no-ssl

# www → non-www redirect
./scripts/site-create.sh site example.com php-traefik \
  --aliases www.example.com --redirect-aliases
```

### List Sites

```bash
./scripts/site-list.sh          # Table: NAME, URL, TEMPLATE, MODE, STATUS
./scripts/site-list.sh --json   # Same data as JSON
```

### Update a Site

```bash
# Rebuild with the latest base image (security updates) and recreate
./scripts/site-update.sh <name>

# Change runtime version, then rebuild
./scripts/site-update.sh <name> --php-version 8.4

# Change resource limits
./scripts/site-update.sh <name> --cpu 2 --memory 1G

# Switch site mode (--force skips the confirmation prompt)
./scripts/site-update.sh <name> --mode prod
./scripts/site-update.sh <name> --mode dev --force

# Full rebuild without layer cache
./scripts/site-update.sh <name> --no-cache

# Refresh the base image of every site
./scripts/site-update.sh --all

# Interactive mode
./scripts/site-update.sh
```

The container is only recreated if it was running; stopped sites are just rebuilt. Run `./scripts/site-update.sh --all` periodically to pick up base image security updates.

Switching mode regenerates `compose.yaml` and `Dockerfile` from the template and re-applies the site's configuration from `site.yaml` — **manual edits to those files are lost** (the previous versions are kept as `*.bak`).

### Deploy a Site

```bash
./scripts/site-deploy.sh <name>              # Pull (if git source) + rebuild/restart
./scripts/site-deploy.sh <name> --no-cache   # Prod: full image rebuild
./scripts/site-deploy.sh <name> --no-prune   # Keep old images after a prod deploy
```

For sites created with `--from-git`, pulls the latest code first (fast-forward only, via containerized git — no git needed on the host). Then:

- **prod**: rebuilds the image (code is baked in), recreates the container, prunes dangling images.
- **dev**: restarts the container (live mount; startup reinstalls dependencies).

Private HTTPS repos: embed a deploy token in the URL — `https://TOKEN@github.com/owner/repo.git`.

### Delete a Site

```bash
./scripts/site-delete.sh <name> [--with-db] [--force]
```

Removes the container, the built Docker image, the site files and its Let's Encrypt certificates. With `--with-db` (or on interactive confirmation), the site's MySQL database and user are also deleted — a safety dump is saved to `backups/` first. `--force` alone never touches the database.

Prod sites: the `<site>_app-data` volume is removed too, but a safety archive `backups/<site>_data_<timestamp>.tar.gz` is always written first (even with `--force`). Restore it manually with `docker run --rm -i -v <site>_app-data:/data alpine tar xzf - -C /data < archive.tar.gz`.

### Backup a Site

```bash
# Files only
./scripts/site-backup.sh <name>

# Files + database dump
./scripts/site-backup.sh <name> --with-db
```

Backups are stored as `backups/<name>_<timestamp>.tar.gz` with `chmod 600` (they contain `.env` secrets). For prod sites, the `/app/data` volume is embedded as `data.tar.gz` and recreated on restore — stop the container first for a guaranteed-consistent SQLite backup (a live capture may be mid-write).

### Restore a Site

```bash
./scripts/site-restore.sh backups/<name>_<timestamp>.tar.gz
```

### Default Site (IP Access)

Configure what happens when someone reaches the server by IP address:

```bash
./scripts/default-site.sh                           # Interactive
./scripts/default-site.sh --mode page               # Static page
./scripts/default-site.sh --mode 404                # Return 404
./scripts/default-site.sh --mode redirect --redirect-url https://example.com
./scripts/default-site.sh --mode disable            # Remove
```

---

## Site Modes

Every site is created in one of two modes (stored in `site.yaml`, absent = `dev`):

| | `dev` (default) | `prod` |
| --- | --- | --- |
| Code | Bind mount `./app` — changes apply live | Baked into the image at build time |
| Dependencies | Installed at container start | Frozen via lockfile at image build |
| Image | Full toolchain (composer, npm, git...) | Minimal runtime, no devtools (PHP: 747 MB vs 1.03 GB dev) |
| User | root | Non-root `app` (PHP: FrankenPHP drops privileges itself) |
| Process | Node.js: PM2; crash keeps container alive for debugging | Direct process, `init: true`; crash = exit = restart policy |
| New code | Edit files / `docker compose restart` | `site-deploy.sh` or `site-update.sh` (rebuild) |

Switch anytime: `./scripts/site-update.sh <name> --mode <dev|prod>`.

### Prod Build Requirements

Prod builds fail fast (missing lockfile, `start` script, `go.mod`, broken `composer install`) rather than ship a broken image:

| Runtime | Required in `app/` |
|---------|--------------------|
| Go | `go.mod` + entry point (`main.go`, `cmd/server/main.go` or `cmd/main.go`) — static binary, `CGO_ENABLED=0` |
| Node.js | `package.json` + `package-lock.json` + `"start"` script (runs via `node --run start`) |
| Bun | `package.json` + `bun.lock`/`bun.lockb` + `"start"` script (runs via `bun run start`) |
| PHP | `public/index.php` — prod always serves `/app/public` (missing index = 404, not a build failure). `composer.json` triggers `composer install --no-dev`; `package.json` with a `build` script triggers `npm ci && npm run build` (requires `package-lock.json`) |

**Bun gotcha**: a dependency-less app has no lockfile (bun deletes empty ones). Add any real dependency to get a `bun.lock`.

**PHP gotchas**: a dev site with `index.php` at the root of `app/` must move it under `app/public/` before switching to prod. `require-dev` packages (e.g. laravel-debugbar) are absent in prod — code referencing them breaks. Compose sets `APP_ENV=production`, which overrides the app's own `.env` (container env wins).

**Laravel**: fits the prod layout natively (`public/index.php`). `storage/` and `bootstrap/cache` are writable but ephemeral (baked image) — point SQLite and uploads at `/app/data`, or add a volume for `storage/` manually if it must persist.

### Persistent Data in Prod

The prod container filesystem is immutable — anything written inside is lost on redeploy. Put mutable data (SQLite, uploads) in `/app/data`: it's a named volume (`<site>_app-data`) that survives rebuilds and redeploys.

### Why No PM2 in Prod

One container = one process. Docker's restart policy and healthcheck replace PM2; `pm2-runtime` would mask crashes from Docker. Dev keeps PM2 for compatibility. Apps should handle `SIGTERM` for graceful shutdown (`init: true` forwards it).

---

## Templates

| Template | Runtime | Routing | Use Case |
|----------|---------|---------|----------|
| `php-traefik` | FrankenPHP | Traefik + SSL | Production PHP |
| `php-standalone` | FrankenPHP | Direct ports 80/443 | Single-site servers |
| `nodejs-traefik` | Node.js + PM2 | Traefik + SSL | Production Node.js |
| `nodejs-standalone` | Node.js + PM2 | Direct port 3000 | Single-site servers |
| `bun-traefik` | Bun | Traefik + SSL | Production Bun/Elysia |
| `bun-standalone` | Bun | Direct port 3000 | Single-site Bun |
| `go-traefik` | Go | Traefik + SSL | Production Go APIs |
| `go-standalone` | Go | Direct port 8080 | Single-site Go |

### Runtime Versions

| Runtime | Available | Default |
|---------|-----------|---------|
| PHP | 8.2, 8.3, 8.4, 8.5 | 8.5 |
| Node.js | 22, 24 | 24 |
| Bun | 1, 1.3 | 1.3 |
| Go | 1.25, 1.26 | 1.26 |

Versions are set in `sites/<name>/.env` and passed as Docker build args. To change after creation: `./scripts/site-update.sh <name> --<runtime>-version <ver>` (updates `.env` + manifest, rebuilds, recreates).

Each runtime has one shared multi-stage Dockerfile in `templates/dockerfiles/` (stages: `base` → `build` → `prod` → `dev`). The site's `compose.yaml` selects the stage via `build.target`; the `dev` stage is last so images built without a target (pre-existing sites) stay dev.

---

## Frameworks

Framework installers run inside a temporary container during site creation. Each is tied to a specific runtime — incompatible combinations are rejected upfront.

| Framework | Runtime | DB | Notes |
|-----------|---------|----|-------|
| `laravel` | PHP | Required | `composer create-project`, `.env` auto-configured |
| `wordpress` | PHP | Required | Latest WP download, `wp-config.php` reads DB from env |
| `nextjs` | Node.js | Optional | `create-next-app` with TypeScript + Tailwind |
| `elysia` | Bun | Optional | Minimal Elysia server on `:3000` |
| `gin` | Go | Optional | Minimal Gin server on `:8080` |

### Database Credentials

When `--with-db` is used:

1. A MySQL user and database are created (`{site_name}` and `{site_name}_db`).
2. Credentials are written to `sites/<name>/.env` and forwarded to the container via `compose.yaml`'s `environment:` section.
3. Framework-specific files are patched:
   - **Laravel**: `app/.env` gets the real `DB_PASSWORD`.
   - **WordPress**: `wp-config.php` reads from `getenv()` — no patching needed.
   - **Others**: the app reads `process.env.DB_*` / `os.Getenv("DB_*")`.

Credentials are displayed once at the end of site creation. They're not stored outside the site's `.env`.

---

## Domain Configuration

**Multiple domains, same content:**

```bash
./scripts/site-create.sh site example.com php-traefik \
  --aliases "www.example.com,blog.example.com"
```

**301 redirect to main domain:**

```bash
./scripts/site-create.sh site example.com php-traefik \
  --aliases www.example.com --redirect-aliases
```

**Local dev (no SSL):**

```bash
./scripts/site-create.sh dev dev.local php-traefik --no-ssl
# Add to /etc/hosts: 127.0.0.1 dev.local
```

---

## Development Workflow

### Commands in Containers (Zero Host Install)

No runtime needed on the host — composer, npm, bun, go all run inside the site's container:

```bash
./scripts/site-shell.sh <name>                 # Interactive shell (bash, falls back to sh)
./scripts/site-run.sh <name> composer install  # One-off command, exit code preserved
./scripts/site-run.sh <name> -- npm run build --verbose   # '--' passes flags untouched
```

Both require a running container. In prod mode they warn: the container filesystem is immutable, changes are lost on redeploy.

### Per-site Docker commands

```bash
cd sites/<name>

sudo docker compose up -d          # Start
sudo docker compose down           # Stop
sudo docker compose logs -f        # Follow logs
sudo docker compose up -d --build  # Rebuild (after .env changes)
```

### Your app files live in `sites/<name>/app/`

- **PHP**: FrankenPHP serves `SERVER_ROOT` (`/app/public` by default; dev adjusts it to `/app/public/public` for Laravel, prod always serves `/app/public`).
- **Node.js**: dev: PM2 reads `ecosystem.config.js` from `/app/`; prod: `node --run start`.
- **Bun**: Runs `bun run start` from `package.json`.
- **Go**: Builds and runs `main.go` / `cmd/server/main.go` / `cmd/main.go` (prod: compiled at image build).

In dev mode `app/` is bind-mounted (edits apply live); in prod mode it's copied into the image at build time (rebuild to apply).

---

## Security

- **MySQL**: passwords passed via `MYSQL_PWD` env var (never visible in `ps`).
- **Containers**: `no-new-privileges:true` on all templates.
- **Prod images**: non-root user, no devtools; `.dockerignore` keeps `.env` (DB secrets) and `site.yaml` out of the image.
- **Traefik**: dashboard disabled, Docker socket read-only, HSTS.
- **SSL**: automatic Let's Encrypt certificates (`acme.json` with permissions 600).
- **Backups**: created with `chmod 600` (contain `.env` secrets).
- **Input validation**: strict site names, URLs, and framework/runtime compatibility checks.
- **Cleanup traps**: interrupted runs (Ctrl+C) clean up temporary install containers.

---

## Troubleshooting

### Container won't start

```bash
cd sites/<name> && sudo docker compose logs
sudo docker ps -a
```

### SSL certificate issues

```bash
cd config/traefik && sudo docker compose logs
ls -la config/traefik/acme.json  # Must be 600
```

Use `--no-ssl` during local development (`.local` domains won't get real certs anyway).

### MySQL unreachable from a container

From any site container:

- Host: `mysql`
- Port: `3306`
- User/password: set in `config/mysql/.env` (or per-site credentials created via `--with-db`)

### Runtime version changed but nothing happens

After editing `PHP_VERSION` / `NODE_VERSION` / `BUN_VERSION` / `GO_VERSION` in a site's `.env`, rebuild:

```bash
cd sites/<name> && sudo docker compose up -d --build
```

### Prod build fails

The build validates the app before shipping — the error message names the missing piece:

- **No lockfile**: Node.js needs `package-lock.json` (`npm install --package-lock-only`), Bun needs `bun.lock`/`bun.lockb` (`bun install` — and at least one dependency, bun deletes empty lockfiles).
- **No `start` script**: Node.js and Bun prod images run the `start` script from `package.json`.
- **No `go.mod` / entry point**: Go needs a module and `main.go`, `cmd/server/main.go` or `cmd/main.go`.
- **`composer install` fails**: fix `composer.json`/`composer.lock` in `app/` and rebuild.

### Prod site loses data on redeploy

Only `/app/data` (named volume) persists. Move SQLite files and uploads there — the rest of the container filesystem is rebuilt from the image on every deploy.

---

## Tests

```bash
./tests/smoke-test.sh
```

Validates script syntax, template structure, placeholders, security options, framework metadata, and that MySQL credentials are never passed via `-p` arguments.
