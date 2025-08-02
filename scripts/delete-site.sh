#!/bin/bash

SITES_DIR="sites"

if [ -z "$1" ]; then
  echo "Usage: $0 <site-name>"
  exit 1
fi

SITE_NAME=$1
SITE_DIR="$SITES_DIR/$SITE_NAME"

if [ ! -d "$SITE_DIR" ]; then
  echo "Error: Site '$SITE_NAME' does not exist."
  exit 1
fi

# Stop and remove containers
cd "$SITE_DIR"
sudo docker compose down

# Delete the directory
cd ..
rm -rf "$SITE_NAME"

echo "🗑️ Site '$SITE_NAME' has been deleted."
