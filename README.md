# Docker-Set

Docker environment for managing multiple web applications with shared infrastructure (Traefik + MySQL).

## Project Structure

```
docker-set/
├── config/                   # Infrastructure configuration
│   ├── traefik/              # Reverse proxy + SSL
│   └── mysql/                # Shared database
├── lib/                      # Shared bash libraries
│   ├── common.sh             # Colors, logging, validation, utilities
│   ├── site.sh               # Site creation, aliases, manifest, versions
│   ├── database.sh           # MySQL operations, credential injection
│   └── framework.sh          # Framework installation
├── scripts/                  # Management scripts
│   ├── setup.sh              # Initial setup wizard
│   ├── site-create.sh        # Create a site (+ DB, + framework)
│   ├── site-delete.sh        # Delete a site
│   ├── site-list.sh          # List sites and their status
│   ├── site-backup.sh        # Backup site files + DB
│   ├── site-restore.sh       # Restore from a backup
│   └── default-site.sh       # Configure default response for IP access
├── templates/                # Site templates
│   ├── dockerfiles/          # Shared Dockerfiles (one per runtime)
│   ├── php-traefik/          # compose.yaml + .env.dist
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
| `--php-version <ver>` | PHP version: 8.2, 8.3, 8.4 | `8.4` |
| `--node-version <ver>` | Node.js version: 22, 24 | `24` |
| `--bun-version <ver>` | Bun version: 1, 1.3 | `1.3` |
| `--go-version <ver>` | Go version: 1.23, 1.24 | `1.24` |
| `--framework <name>` | Install a framework (see below) | — |
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

# Local dev without SSL
./scripts/site-create.sh dev dev.local php-traefik --no-ssl

# www → non-www redirect
./scripts/site-create.sh site example.com php-traefik \
  --aliases www.example.com --redirect-aliases
```

### List Sites

```bash
./scripts/site-list.sh
```

### Delete a Site

```bash
./scripts/site-delete.sh <name> [--force]
```

### Backup a Site

```bash
# Files only
./scripts/site-backup.sh <name>

# Files + database dump
./scripts/site-backup.sh <name> --with-db
```

Backups are stored as `backups/<name>_<timestamp>.tar.gz` with `chmod 600` (they contain `.env` secrets).

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
| PHP | 8.2, 8.3, 8.4 | 8.4 |
| Node.js | 22, 24 | 24 |
| Bun | 1, 1.3 | 1.3 |
| Go | 1.23, 1.24 | 1.24 |

Versions are set in `sites/<name>/.env` and passed as Docker build args. To change after creation, edit `.env` and rebuild: `docker compose up -d --build`.

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

### Per-site Docker commands

```bash
cd sites/<name>

sudo docker compose up -d          # Start
sudo docker compose down           # Stop
sudo docker compose logs -f        # Follow logs
sudo docker compose up -d --build  # Rebuild (after .env changes)
```

### Your app files live in `sites/<name>/app/`

- **PHP**: FrankenPHP serves `SERVER_ROOT` (`/app/public` by default, `/app/public/public` for Laravel).
- **Node.js**: PM2 reads `ecosystem.config.js` from `/app/`.
- **Bun**: Runs `bun run start` from `package.json`.
- **Go**: Builds and runs `main.go` / `cmd/server/main.go` / `cmd/main.go`.

---

## Security

- **MySQL**: passwords passed via `MYSQL_PWD` env var (never visible in `ps`).
- **Containers**: `no-new-privileges:true` on all templates.
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

---

## Tests

```bash
./tests/smoke-test.sh
```

Validates script syntax, template structure, placeholders, security options, framework metadata, and that MySQL credentials are never passed via `-p` arguments.
