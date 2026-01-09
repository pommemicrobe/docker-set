# Docker-Set

Docker environment for managing multiple web applications with shared infrastructure (Traefik + MySQL).

## Project Structure

```
docker-set/
├── config/                 # Infrastructure configuration
│   ├── traefik/           # Reverse proxy + SSL
│   └── mysql/             # Shared database
├── lib/                   # Script library
│   └── common.sh          # Shared functions
├── scripts/               # Management scripts
│   ├── setup.sh           # Initial setup
│   ├── site-create.sh     # Create a site
│   ├── site-delete.sh     # Delete a site
│   └── site-add-framework.sh
├── templates/             # Site templates
│   ├── php-standalone/
│   ├── php-traefik/
│   ├── nodejs-standalone/
│   └── nodejs-traefik/
├── frameworks/            # Framework templates
├── sites/                 # Deployed sites
└── backups/               # Backups
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

## Detailed Installation

### Prerequisites

- Docker and Docker Compose installed
- Sudo access

### Initial Setup

The `setup.sh` script automatically configures:
- Docker network `web`
- Traefik (reverse proxy + SSL certificates)
- MySQL (shared database)

```bash
./scripts/setup.sh
```

The script will prompt for:
1. **Email** for Let's Encrypt (SSL certificates)
2. **MySQL password** (can be auto-generated)

### Manual Configuration (Alternative)

If you prefer manual setup:

```bash
# Create Docker network
sudo docker network create web

# Configure Traefik
cd config/traefik
cp traefik.yaml.dist traefik.yaml
cp acme.json.dist acme.json
chmod 600 acme.json
# Edit traefik.yaml and replace ACME_EMAIL
sudo docker compose up -d

# Configure MySQL
cd ../mysql
cp .env.dist .env
# Edit .env and set MYSQL_ROOT_PASSWORD
sudo docker compose up -d
```

---

## Management Scripts

### `site-create.sh` - Create a Site

```bash
./scripts/site-create.sh <name> <url> <template> [options]
```

**Arguments:**
- `name`: Site name (lowercase letters, numbers, hyphens)
- `url`: Site URL (e.g., my-site.com)
- `template`: Template to use

**Options:**
- `--no-start`: Don't start the container
- `--help`: Show help

**Examples:**
```bash
# PHP site with Traefik (automatic SSL)
./scripts/site-create.sh my-blog my-blog.com php-traefik

# NodeJS site for local development
./scripts/site-create.sh api-dev localhost:3000 nodejs-standalone --no-start
```

### `site-delete.sh` - Delete a Site

```bash
./scripts/site-delete.sh <name> [options]
```

**Options:**
- `--force`: Delete without confirmation
- `--help`: Show help

**Example:**
```bash
./scripts/site-delete.sh my-blog
```

### `site-add-framework.sh` - Install a Framework

```bash
./scripts/site-add-framework.sh <site> <framework>
```

**Example:**
```bash
./scripts/site-add-framework.sh my-blog laravel
```

---

## Available Templates

### PHP Templates

| Template | Description | Ports |
|----------|-------------|-------|
| `php-standalone` | Direct PHP, no reverse proxy | 80, 443 |
| `php-traefik` | PHP with Traefik (auto SSL) | Via Traefik |

**Features:**
- Base: FrankenPHP
- Extensions: PDO MySQL, GD, Intl, Zip, OPcache, MySQLi
- Tools: Composer, Node.js, npm, git

### NodeJS Templates

| Template | Description | Ports |
|----------|-------------|-------|
| `nodejs-standalone` | Direct NodeJS | 3000 |
| `nodejs-traefik` | NodeJS with Traefik (auto SSL) | Via Traefik |

**Features:**
- Base: Node.js 22 LTS (Alpine)
- Process Manager: PM2 (auto-restart, watch mode)
- Dependencies installed at startup

---

## Development Workflow

### 1. Create a site

```bash
./scripts/site-create.sh my-app my-app.com php-traefik
```

### 2. Add your code

```bash
# Your files go in:
sites/my-app/app/
```

### 3. Manage the container

```bash
# Start
cd sites/my-app && sudo docker compose up -d

# Stop
cd sites/my-app && sudo docker compose down

# Logs
cd sites/my-app && sudo docker compose logs -f
```

### 4. Access

- **Traefik templates:** `https://my-app.com`
- **Standalone templates:** `http://localhost:3000` (NodeJS) or `http://localhost` (PHP)

---

## NodeJS - Required Files

For NodeJS templates, your `app/` directory must contain:

```
app/
├── package.json         # Dependencies
├── index.js             # Entry point (or other)
└── ecosystem.config.js  # PM2 configuration
```

**Example ecosystem.config.js:**
```javascript
module.exports = {
  apps: [{
    name: 'my-app',
    script: 'index.js',
    instances: 1,
    autorestart: true,
    watch: true,
    max_memory_restart: '1G'
  }]
};
```

---

## Security

- **Traefik:** Dashboard disabled, Docker socket read-only
- **Containers:** `no-new-privileges` option enabled
- **MySQL:** Strong password auto-generated
- **SSL:** Automatic Let's Encrypt certificates
- **Scripts:** Strict input validation, confirmation before deletion

---

## Troubleshooting

### Container won't start

```bash
# Check logs
cd sites/<site> && sudo docker compose logs

# Check status
sudo docker ps -a
```

### SSL certificate issues

```bash
# Check Traefik logs
cd config/traefik && sudo docker compose logs

# Check permissions
ls -la config/traefik/acme.json  # Must be 600
```

### MySQL unreachable

```bash
# From a container, use hostname 'mysql'
# Host: mysql
# Port: 3306
# User: root
# Password: (defined in config/mysql/.env)
```
