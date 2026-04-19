#!/bin/sh
# WordPress installer — runs inside the site container
# Env: SITE_NAME, SITE_URL, APP_DIR (provided by framework.sh)
set -eu

FRAMEWORK_DIR="/tmp/.framework"

# Download and extract WordPress directly into APP_DIR
# APP_DIR is already the document root (/app/public inside the container,
# mounted from ./app/ on the host), so no extra nesting is needed.
curl -sL 'https://wordpress.org/latest.zip' -o /tmp/wordpress.zip
unzip -q /tmp/wordpress.zip -d /tmp
mv /tmp/wordpress/* "$APP_DIR/"
mv /tmp/wordpress/.[!.]* "$APP_DIR/" 2>/dev/null || true
rm -f /tmp/wordpress.zip

# Copy config files from framework template
if [ -f "$FRAMEWORK_DIR/public/wp-config.php" ]; then
    cp -f "$FRAMEWORK_DIR/public/wp-config.php" "$APP_DIR/"

    # Escape special characters for sed
    ESCAPED_NAME=$(printf '%s' "$SITE_NAME" | sed 's/[\\&|]/\\&/g')
    ESCAPED_URL=$(printf '%s' "$SITE_URL" | sed 's/[\\&|]/\\&/g')

    sed -i "s|SITE_NAME|$ESCAPED_NAME|g" "$APP_DIR/wp-config.php"
    sed -i "s|SITE_URL|$ESCAPED_URL|g" "$APP_DIR/wp-config.php"
fi

if [ -f "$FRAMEWORK_DIR/public/.htaccess" ]; then
    cp -f "$FRAMEWORK_DIR/public/.htaccess" "$APP_DIR/"
fi

echo ""
echo "Next steps:"
echo "  1. Generate security keys: https://api.wordpress.org/secret-key/1.1/salt/"
echo "  2. Update keys in wp-config.php"
echo "  3. Visit your site to complete WordPress setup"
