#!/bin/bash

FRAMEWORKS_DIR="template-frameworks"
SITES_DIR="sites"

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <site-name> <framework-name>"
  echo "Available frameworks:"
  ls -1 "$FRAMEWORKS_DIR" 2>/dev/null || echo "No frameworks available yet"
  echo ""
  echo "Available sites:"
  ls -1 "$SITES_DIR" 2>/dev/null || echo "No sites created yet"
  exit 1
fi

SITE_NAME=$1
FRAMEWORK_NAME=$2
FRAMEWORK_DIR="$FRAMEWORKS_DIR/$FRAMEWORK_NAME"
SITE_DIR="$SITES_DIR/$SITE_NAME"
APP_DIR="$SITE_DIR/app"

# Check framework exists
if [ ! -d "$FRAMEWORK_DIR" ]; then
  echo "❌ Error: Framework '$FRAMEWORK_NAME' does not exist."
  echo "Available frameworks:"
  ls -1 "$FRAMEWORKS_DIR" 2>/dev/null
  exit 1
fi

# Check site exists
if [ ! -d "$SITE_DIR" ]; then
  echo "❌ Error: Site '$SITE_NAME' does not exist."
  echo "Available sites:"
  ls -1 "$SITES_DIR" 2>/dev/null
  exit 1
fi

# Check if app directory has content (warn user)
if [ "$(ls -A "$APP_DIR" 2>/dev/null)" ]; then
  echo "⚠️  Warning: Site '$SITE_NAME' app directory is not empty."
  echo "Current contents:"
  ls -la "$APP_DIR"
  echo ""
  read -p "Do you want to continue? This will overwrite existing files. (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 1
  fi
fi

# Copy framework to site app directory
echo "📦 Installing framework '$FRAMEWORK_NAME' to site '$SITE_NAME'..."
cp -r "$FRAMEWORK_DIR"/* "$APP_DIR/"

# Replace placeholders if they exist
ENV_FILE="$SITE_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  SITE_URL=$(grep "SITE_URL=" "$ENV_FILE" | cut -d'=' -f2)
  
  # Replace placeholders in framework files
  find "$APP_DIR" -type f \( -name "*.php" -o -name "*.js" -o -name "*.json" -o -name "*.env*" -o -name "*.config.*" \) -exec sed -i '' "s|SITE_NAME|$SITE_NAME|g" {} \;
  find "$APP_DIR" -type f \( -name "*.php" -o -name "*.js" -o -name "*.json" -o -name "*.env*" -o -name "*.config.*" \) -exec sed -i '' "s|SITE_URL|$SITE_URL|g" {} \;
fi

echo "✅ Framework '$FRAMEWORK_NAME' installed successfully in site '$SITE_NAME'!"
echo ""
echo "📍 Next steps:"
echo "   1. Check the app directory: $APP_DIR"
echo "   2. Configure any framework-specific settings"
echo "   3. Restart the container: cd $SITE_DIR && sudo docker compose restart"
echo ""
echo "📋 Framework files installed:"
find "$APP_DIR" -maxdepth 2 -type f | head -10