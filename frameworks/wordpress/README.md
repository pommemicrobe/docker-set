# WordPress Framework

WordPress is automatically downloaded from wordpress.org during site creation.

## Installation

```bash
./scripts/site-create.sh my-wordpress my-wordpress.com php-traefik --framework wordpress --with-db
```

This will:
1. Create the site from php-traefik template
2. Download WordPress latest.zip into `sites/<name>/app/`
3. Copy the pre-configured `wp-config.php`
4. Create database user; credentials are forwarded to the container via `compose.yaml` (with `--with-db`)

## Post-installation

1. **Generate security keys**: https://api.wordpress.org/secret-key/1.1/salt/
2. **Update keys** in `sites/<name>/app/wp-config.php`
3. **Visit your site** to complete the WordPress setup wizard

## Configuration

### Database Credentials

`wp-config.php` reads credentials via `getenv()`. The PHP template forwards the
following environment variables from the site's `.env` to the container:

| Variable | Source | Default |
|----------|--------|---------|
| `DB_HOST` | site `.env` | `mysql` |
| `DB_DATABASE` | site `.env` | `{site_name}_db` |
| `DB_USERNAME` | site `.env` | `{site_name}` |
| `DB_PASSWORD` | site `.env` (auto-injected with `--with-db`) | (empty) |
| `WP_DEBUG` | container env | `false` |

### Security Features

- File editing disabled (`DISALLOW_FILE_EDIT`)
- SSL enforced for admin behind HTTPS proxy
- Security headers in `.htaccess`
- Protected sensitive files

## Files

- `install.sh` - Installation script (downloads WordPress)
- `public/wp-config.php` - Pre-configured WordPress config
- `public/.htaccess` - Security rules
