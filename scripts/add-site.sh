#!/bin/bash

TEMPLATES_DIR="templates"
SITES_DIR="sites"

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <site-name> <template-name>"
  echo "Available templates:"
  ls -1 "$TEMPLATES_DIR"
  exit 1
fi

SITE_NAME=$1
TEMPLATE_NAME=$2
TEMPLATE_DIR="$TEMPLATES_DIR/$TEMPLATE_NAME"
NEW_SITE_DIR="$SITES_DIR/$SITE_NAME"

# Check template exists
if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "Error: Template '$TEMPLATE_NAME' does not exist."
  exit 1
fi

# Check site doesn't already exist
if [ -d "$NEW_SITE_DIR" ]; then
  echo "Error: Site '$SITE_NAME' already exists."
  exit 1
fi

# Create site from template
cp -r "$TEMPLATE_DIR" "$NEW_SITE_DIR"

# Optional: replace placeholders
find "$NEW_SITE_DIR" -type f -exec sed -i "s/{{SITE_NAME}}/$SITE_NAME/g" {} \;

echo "✅ Site '$SITE_NAME' created from template '$TEMPLATE_NAME'."

# Launch container
cd "$NEW_SITE_DIR"
sudo docker compose up -d
