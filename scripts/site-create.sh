#!/usr/bin/env bash
#
# site-create.sh - Créer un nouveau site depuis un template
#
# Usage: ./scripts/site-create.sh <site-name> <site-url> <template-name> [--no-start]
#

# Charger la bibliothèque commune
source "$(dirname "$0")/../lib/common.sh"

# =============================================================================
# AIDE
# =============================================================================

show_help() {
    echo "Usage: $0 <site-name> <site-url> <template-name> [options]"
    echo ""
    echo "Arguments:"
    echo "  site-name     Nom du site (lettres minuscules, chiffres, tirets)"
    echo "  site-url      URL du site (ex: mon-site.com ou localhost:3000)"
    echo "  template-name Nom du template à utiliser"
    echo ""
    echo "Options:"
    echo "  --no-start    Ne pas démarrer le container après création"
    echo "  --help, -h    Afficher cette aide"
    echo ""
    echo "Templates disponibles:"
    ls -1 "$TEMPLATES_DIR" 2>/dev/null | sed 's/^/  - /'
    echo ""
    echo "Exemples:"
    echo "  $0 mon-blog mon-blog.com php-traefik"
    echo "  $0 api-dev localhost:3000 nodejs-standalone --no-start"
}

# =============================================================================
# ARGUMENTS
# =============================================================================

NO_START=false

# Parser les arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-start)
            NO_START=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# Restaurer les arguments positionnels
set -- "${POSITIONAL[@]}"

# Vérifier le nombre d'arguments
if [[ $# -lt 3 ]]; then
    log_error "Arguments manquants"
    echo ""
    show_help
    exit 1
fi

SITE_NAME="$1"
SITE_URL="$2"
TEMPLATE_NAME="$3"

# =============================================================================
# VALIDATION
# =============================================================================

log_info "Validation des paramètres..."

# Valider le nom du site
if ! validate_site_name "$SITE_NAME"; then
    exit 1
fi

# Valider l'URL
if ! validate_url "$SITE_URL"; then
    exit 1
fi

# Valider le template
if ! validate_template_name "$TEMPLATE_NAME"; then
    exit 1
fi

# Vérifier que le site n'existe pas déjà
if [[ -d "$SITES_DIR/$SITE_NAME" ]]; then
    log_error "Le site '$SITE_NAME' existe déjà"
    log_info "Pour le supprimer: ./scripts/site-delete.sh $SITE_NAME"
    exit 1
fi

log_ok "Paramètres validés"

# =============================================================================
# CRÉATION
# =============================================================================

print_header "Création du site '$SITE_NAME'"

TEMPLATE_DIR="$TEMPLATES_DIR/$TEMPLATE_NAME"
NEW_SITE_DIR="$SITES_DIR/$SITE_NAME"

# Configurer le nettoyage en cas d'erreur
set_cleanup_dir "$NEW_SITE_DIR"

# Copier le template
log_info "Copie du template '$TEMPLATE_NAME'..."
cp -r "$TEMPLATE_DIR" "$NEW_SITE_DIR"
log_ok "Template copié"

# Renommer .env.dist en .env
if [[ -f "$NEW_SITE_DIR/.env.dist" ]]; then
    mv "$NEW_SITE_DIR/.env.dist" "$NEW_SITE_DIR/.env"
    log_ok "Fichier .env créé"
fi

# Remplacer les placeholders dans .env
ENV_FILE="$NEW_SITE_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    log_info "Configuration du fichier .env..."
    sed_inplace "s|SITE_NAME=SITE_NAME|SITE_NAME=$SITE_NAME|g" "$ENV_FILE"
    sed_inplace "s|SITE_URL=SITE_URL|SITE_URL=$SITE_URL|g" "$ENV_FILE"
    log_ok "Variables d'environnement configurées"
fi

# Remplacer SERVICE_NAME dans compose.yaml
COMPOSE_FILE="$NEW_SITE_DIR/compose.yaml"
if [[ -f "$COMPOSE_FILE" ]]; then
    log_info "Configuration de compose.yaml..."
    sed_inplace "s|SERVICE_NAME|$SITE_NAME|g" "$COMPOSE_FILE"
    log_ok "Service Docker configuré"
fi

# Désactiver le nettoyage (succès)
clear_cleanup_dir

# =============================================================================
# DÉMARRAGE
# =============================================================================

log_ok "Site '$SITE_NAME' créé avec succès"
echo ""
log_info "Emplacement: $NEW_SITE_DIR"
log_info "URL: $SITE_URL"
log_info "Template: $TEMPLATE_NAME"

if [[ "$NO_START" == true ]]; then
    echo ""
    log_info "Pour démarrer le site:"
    echo "  cd $NEW_SITE_DIR && sudo docker compose up -d"
else
    echo ""
    if confirm "Démarrer le container maintenant ?" "y"; then
        log_info "Démarrage du container..."
        (cd "$NEW_SITE_DIR" && docker compose up -d)
        log_ok "Container démarré"

        # Afficher le statut
        sleep 2
        echo ""
        log_info "État du container:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "$SITE_NAME|NAMES"
    else
        log_info "Pour démarrer plus tard:"
        echo "  cd $NEW_SITE_DIR && sudo docker compose up -d"
    fi
fi

echo ""
log_info "Fichiers de l'application dans: $NEW_SITE_DIR/app/"
