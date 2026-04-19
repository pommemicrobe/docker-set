# Laravel Framework

Laravel is installed via the official Composer Docker image during site creation. No local Composer installation required.

## Installation

```bash
./scripts/site-create.sh my-laravel my-laravel.com php-traefik --framework laravel --with-db
```

This will:
1. Create the site from php-traefik template
2. Run `composer create-project` via Docker
3. Configure `.env` with your site settings
4. Create database user and inject the generated password into `app/.env` (with `--with-db`)

## Post-installation

1. **Run migrations**: `docker exec -it <name> php artisan migrate`
2. **Visit your site**

## Configuration

With `--with-db`, the `.env` file is fully configured — no manual password step required:

| Setting | Value |
|---------|-------|
| `APP_NAME` | Your site name |
| `APP_URL` | https://your-site-url |
| `DB_CONNECTION` | mysql |
| `DB_HOST` | mysql (shared container) |
| `DB_DATABASE` | {site_name}_db |
| `DB_USERNAME` | {site_name} |
| `DB_PASSWORD` | auto-generated, injected post-install |

## Directory Structure

Laravel uses `public/` as the web root, which matches the php-traefik template configuration.

```
sites/<name>/app/
├── app/
├── bootstrap/
├── config/
├── database/
├── public/          # Web root (served by FrankenPHP)
├── resources/
├── routes/
├── storage/
├── .env
└── composer.json
```

## Files

- `install.sh` - Installation script (uses Docker Composer image)
