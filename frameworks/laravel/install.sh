#!/bin/sh
# Laravel installer — runs inside the site container
# Env: SITE_NAME, SITE_URL (provided by framework.sh)
set -eu

cd /app

composer create-project --prefer-dist --no-interaction laravel/laravel .

# Configure Laravel .env
if [ -f .env ]; then
    DB_NAME=$(echo "$SITE_NAME" | tr '-' '_')_db
    DB_USER=$(echo "$SITE_NAME" | tr '-' '_')

    # Escape special characters for sed
    ESCAPED_NAME=$(printf '%s' "$SITE_NAME" | sed 's/[\\&|]/\\&/g')
    ESCAPED_URL=$(printf '%s' "$SITE_URL" | sed 's/[\\&|]/\\&/g')
    ESCAPED_DB_NAME=$(printf '%s' "$DB_NAME" | sed 's/[\\&|]/\\&/g')
    ESCAPED_DB_USER=$(printf '%s' "$DB_USER" | sed 's/[\\&|]/\\&/g')

    sed -i "s|APP_NAME=Laravel|APP_NAME=$ESCAPED_NAME|g" .env
    sed -i "s|APP_URL=http://localhost|APP_URL=https://$ESCAPED_URL|g" .env
    sed -i "s|DB_CONNECTION=sqlite|DB_CONNECTION=mysql|g" .env
    sed -i "s|# DB_HOST=127.0.0.1|DB_HOST=mysql|g" .env
    sed -i "s|# DB_PORT=3306|DB_PORT=3306|g" .env
    sed -i "s|# DB_DATABASE=laravel|DB_DATABASE=$ESCAPED_DB_NAME|g" .env
    sed -i "s|# DB_USERNAME=root|DB_USERNAME=$ESCAPED_DB_USER|g" .env
    sed -i "s|# DB_PASSWORD=|DB_PASSWORD=|g" .env
fi

echo ""
echo "Next steps:"
echo "  1. Update DB_PASSWORD in .env"
echo "  2. Run migrations: docker exec -it $SITE_NAME php artisan migrate"
echo "  3. Visit: https://$SITE_URL"
