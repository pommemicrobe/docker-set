# WordPress Framework

WordPress is automatically downloaded from wordpress.org during site creation.

## Installation

```bash
./scripts/site-create.sh my-wordpress my-wordpress.com php-traefik --framework wordpress --with-db
```

This will:
1. Create the site from php-traefik template
2. Download WordPress latest.zip from wordpress.org
3. Configure wp-config.php with your site settings
4. Create database user (with `--with-db` flag)

## Post-installation

1. **Generate security keys**: https://api.wordpress.org/secret-key/1.1/salt/
2. **Update keys** in `sites/<name>/app/public/wp-config.php`
3. **Visit your site** to complete WordPress setup wizard

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_HOST` | Database host | `mysql` |
| `DB_DATABASE` | Database name | `{site_name}_db` |
| `DB_USERNAME` | Database user | `{site_name}` |
| `DB_PASSWORD` | Database password | (empty) |
| `WP_DEBUG` | Enable debug mode | `false` |

### Security Features

- File editing disabled (`DISALLOW_FILE_EDIT`)
- SSL enforced for admin behind HTTPS proxy
- Security headers in `.htaccess`
- Protected sensitive files

## Files

- `install.sh` - Installation script (downloads WordPress)
- `public/wp-config.php` - Pre-configured WordPress config
- `public/.htaccess` - Security rules
