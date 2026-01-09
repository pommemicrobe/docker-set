#!/usr/bin/env bash
#
# site-add-framework.sh - Installer un framework dans un site existant
#
# Usage: ./scripts/site-add-framework.sh <site-name> <framework-name>
#

# Charger la bibliothèque commune
source "$(dirname "$0")/../lib/common.sh"

# =============================================================================
# AIDE
# =============================================================================

show_help() {
    echo "Usage: $0 <site-name> <framework-name>"
    echo ""
    echo "Arguments:"
    echo "  site-name       Nom du site existant"
    echo "  framework-name  Nom du framework à installer"
    echo ""
    echo "Options:"
    echo "  --help, -h      Afficher cette aide"
    echo ""
    echo "Frameworks disponibles:"
    if [[ -d "$FRAMEWORKS_DIR" ]]; then
        ls -1 "$FRAMEWORKS_DIR" 2>/dev/null | sed 's/^/  - /' || echo "  (aucun framework)"
    else
        echo "  (aucun framework)"
    fi
    echo ""
    echo "Sites existants:"
    list_sites
}

# =============================================================================
# ARGUMENTS
# =============================================================================

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Vérifier le nombre d'arguments
if [[ $# -lt 2 ]]; then
    log_error "Arguments manquants"
    echo ""
    show_help
    exit 1
fi

SITE_NAME="$1"
FRAMEWORK_NAME="$2"

SITE_DIR="$SITES_DIR/$SITE_NAME"
APP_DIR="$SITE_DIR/app"
FRAMEWORK_DIR="$FRAMEWORKS_DIR/$FRAMEWORK_NAME"

# =============================================================================
# VALIDATION
# =============================================================================

log_info "Validation des paramètres..."

# Valider le nom du site
if ! validate_site_name "$SITE_NAME"; then
    exit 1
fi

# Vérifier que le site existe
if [[ ! -d "$SITE_DIR" ]]; then
    log_error "Le site '$SITE_NAME' n'existe pas"
    echo ""
    list_sites
    exit 1
fi

# Vérifier que le framework existe
if [[ ! -d "$FRAMEWORK_DIR" ]]; then
    log_error "Le framework '$FRAMEWORK_NAME' n'existe pas"
    echo ""
    log_info "Frameworks disponibles:"
    ls -1 "$FRAMEWORKS_DIR" 2>/dev/null | sed 's/^/  - /' || echo "  (aucun framework)"
    exit 1
fi

# Vérifier que le framework n'est pas vide
if [[ -z "$(ls -A "$FRAMEWORK_DIR" 2>/dev/null)" ]]; then
    log_error "Le framework '$FRAMEWORK_NAME' est vide"
    exit 1
fi

log_ok "Paramètres validés"

# =============================================================================
# VÉRIFICATION CONTENU EXISTANT
# =============================================================================

# Créer le dossier app s'il n'existe pas
mkdir -p "$APP_DIR"

# Vérifier si le dossier app contient déjà des fichiers
if [[ -n "$(ls -A "$APP_DIR" 2>/dev/null)" ]]; then
    log_warn "Le dossier app contient déjà des fichiers:"
    ls -la "$APP_DIR" | head -10 | sed 's/^/  /'
    echo ""

    if ! confirm "Les fichiers existants pourraient être écrasés. Continuer ?"; then
        log_info "Opération annulée"
        exit 0
    fi
fi

# =============================================================================
# INSTALLATION
# =============================================================================

print_header "Installation de '$FRAMEWORK_NAME' dans '$SITE_NAME'"

log_info "Copie des fichiers du framework..."
cp -r "$FRAMEWORK_DIR"/* "$APP_DIR/"
log_ok "Fichiers copiés"

# Récupérer les variables du site
ENV_FILE="$SITE_DIR/.env"
SITE_URL=""
if [[ -f "$ENV_FILE" ]]; then
    SITE_URL=$(grep "^SITE_URL=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || true)
fi

# Remplacer les placeholders dans les fichiers du framework
if [[ -n "$SITE_URL" ]]; then
    log_info "Remplacement des placeholders..."

    # Extensions de fichiers à traiter
    local_extensions=("php" "js" "ts" "json" "yaml" "yml" "env" "conf" "config")

    for ext in "${local_extensions[@]}"; do
        find "$APP_DIR" -type f -name "*.$ext" -exec sh -c '
            for file do
                if grep -q "SITE_NAME\|SITE_URL" "$file" 2>/dev/null; then
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        sed -i "" "s|SITE_NAME|'"$SITE_NAME"'|g; s|SITE_URL|'"$SITE_URL"'|g" "$file"
                    else
                        sed -i "s|SITE_NAME|'"$SITE_NAME"'|g; s|SITE_URL|'"$SITE_URL"'|g" "$file"
                    fi
                fi
            done
        ' sh {} +
    done

    # Traiter aussi les fichiers sans extension qui commencent par .env
    find "$APP_DIR" -type f -name ".env*" -exec sh -c '
        for file do
            if grep -q "SITE_NAME\|SITE_URL" "$file" 2>/dev/null; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i "" "s|SITE_NAME|'"$SITE_NAME"'|g; s|SITE_URL|'"$SITE_URL"'|g" "$file"
                else
                    sed -i "s|SITE_NAME|'"$SITE_NAME"'|g; s|SITE_URL|'"$SITE_URL"'|g" "$file"
                fi
            fi
        done
    ' sh {} +

    log_ok "Placeholders remplacés"
fi

# =============================================================================
# RÉSUMÉ
# =============================================================================

echo ""
log_ok "Framework '$FRAMEWORK_NAME' installé avec succès"

echo ""
log_info "Fichiers installés:"
find "$APP_DIR" -maxdepth 2 -type f | head -15 | sed 's/^/  /'
file_count=$(find "$APP_DIR" -type f | wc -l | tr -d ' ')
if [[ $file_count -gt 15 ]]; then
    echo "  ... et $((file_count - 15)) autres fichiers"
fi

echo ""
log_info "Prochaines étapes:"
echo "  1. Vérifier les fichiers dans: $APP_DIR"
echo "  2. Configurer les paramètres spécifiques au framework"
echo "  3. Redémarrer le container: cd $SITE_DIR && sudo docker compose restart"
