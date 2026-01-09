#!/usr/bin/env bash
#
# site-delete.sh - Supprimer un site existant
#
# Usage: ./scripts/site-delete.sh <site-name> [--force]
#

# Charger la bibliothèque commune
source "$(dirname "$0")/../lib/common.sh"

# =============================================================================
# AIDE
# =============================================================================

show_help() {
    echo "Usage: $0 <site-name> [options]"
    echo ""
    echo "Arguments:"
    echo "  site-name     Nom du site à supprimer"
    echo ""
    echo "Options:"
    echo "  --force, -f   Supprimer sans demander confirmation"
    echo "  --help, -h    Afficher cette aide"
    echo ""
    echo "Sites existants:"
    list_sites
}

# =============================================================================
# ARGUMENTS
# =============================================================================

FORCE=false

# Parser les arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
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
if [[ $# -lt 1 ]]; then
    log_error "Argument manquant: nom du site"
    echo ""
    show_help
    exit 1
fi

SITE_NAME="$1"
SITE_DIR="$SITES_DIR/$SITE_NAME"

# =============================================================================
# VALIDATION
# =============================================================================

# Valider le nom (protection contre injection)
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

# =============================================================================
# CONFIRMATION
# =============================================================================

print_header "Suppression du site '$SITE_NAME'"

# Afficher les infos du site
log_info "Emplacement: $SITE_DIR"

# Vérifier si le container tourne
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${SITE_NAME}$"; then
    log_warn "Le container '$SITE_NAME' est en cours d'exécution"
fi

# Lister les fichiers
log_info "Contenu du site:"
ls -la "$SITE_DIR" 2>/dev/null | head -10 | sed 's/^/  /'

echo ""

# Demander confirmation sauf si --force
if [[ "$FORCE" != true ]]; then
    log_warn "Cette action est IRRÉVERSIBLE"
    if ! confirm "Voulez-vous vraiment supprimer '$SITE_NAME' ?"; then
        log_info "Opération annulée"
        exit 0
    fi
fi

# =============================================================================
# SUPPRESSION
# =============================================================================

# Arrêter le container si nécessaire
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${SITE_NAME}$"; then
    log_info "Arrêt et suppression du container..."
    (cd "$SITE_DIR" && docker compose down --volumes --remove-orphans 2>/dev/null) || true
    log_ok "Container arrêté"
fi

# Supprimer le dossier
log_info "Suppression des fichiers..."
rm -rf "$SITE_DIR"
log_ok "Dossier supprimé"

echo ""
log_ok "Site '$SITE_NAME' supprimé avec succès"
