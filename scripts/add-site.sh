#!/bin/bash

TEMPLATES_DIR="template-images"
SITES_DIR="sites"

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Usage: $0 <site-name> <site-url> <template-name>"
  echo "Available templates:"
  ls -1 "$TEMPLATES_DIR"
  exit 1
fi

SITE_NAME=$1
SITE_URL=$2
TEMPLATE_NAME=$3
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

if [ -f "$NEW_SITE_DIR/.env.dist" ]; then
  mv "$NEW_SITE_DIR/.env.dist" "$NEW_SITE_DIR/.env"
fi

# Replace SITE_NAME and SITE_URL in .env if exists
ENV_FILE="$NEW_SITE_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  sed -i '' "s|SITE_NAME=SITE_NAME|SITE_NAME=$SITE_NAME|" "$ENV_FILE"
  sed -i '' "s|SITE_URL=SITE_URL|SITE_URL=$SITE_URL|" "$ENV_FILE"
fi

# Replace SERVICE_NAME in compose.yaml if exists
COMPOSE_FILE="$NEW_SITE_DIR/compose.yaml"

if [ -f "$COMPOSE_FILE" ]; then
  sed -i '' "s|SERVICE_NAME|$SITE_NAME|g" "$COMPOSE_FILE"
fi

echo "✅ Site '$SITE_NAME' created from template '$TEMPLATE_NAME'."

# Launch container
cd "$NEW_SITE_DIR"
sudo docker compose up -d
