#!/bin/sh
# WordPress installer — runs inside the site container
# Env: SITE_NAME, SITE_URL (provided by framework.sh)
set -eu

FRAMEWORK_DIR="$(dirname "$0")"

# Download and extract WordPress
curl -sL 'https://wordpress.org/latest.zip' -o /tmp/wordpress.zip
unzip -q /tmp/wordpress.zip -d /tmp
mkdir -p /app/public
mv /tmp/wordpress/* /app/public/
rm -f /tmp/wordpress.zip

# Copy config files from framework template
if [ -f "$FRAMEWORK_DIR/public/wp-config.php" ]; then
    cp -f "$FRAMEWORK_DIR/public/wp-config.php" /app/public/

    # Escape special characters for sed
    ESCAPED_NAME=$(printf '%s' "$SITE_NAME" | sed 's/[\\&|]/\\&/g')
    ESCAPED_URL=$(printf '%s' "$SITE_URL" | sed 's/[\\&|]/\\&/g')

    sed -i "s|SITE_NAME|$ESCAPED_NAME|g" /app/public/wp-config.php
    sed -i "s|SITE_URL|$ESCAPED_URL|g" /app/public/wp-config.php
fi

if [ -f "$FRAMEWORK_DIR/public/.htaccess" ]; then
    cp -f "$FRAMEWORK_DIR/public/.htaccess" /app/public/
fi

echo ""
echo "Next steps:"
echo "  1. Generate security keys: https://api.wordpress.org/secret-key/1.1/salt/"
echo "  2. Update keys in wp-config.php"
echo "  3. Visit your site to complete WordPress setup"
