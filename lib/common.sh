#!/usr/bin/env bash
#
# common.sh - Bibliothèque partagée pour les scripts docker-set
#
# Usage: source "$(dirname "$0")/../lib/common.sh"
#

set -euo pipefail

# =============================================================================
# COULEURS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# CHEMINS
# =============================================================================
# Déterminer la racine du projet
if [[ -n "${PROJECT_ROOT:-}" ]]; then
    : # Déjà défini
elif [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$_LIB_DIR")"
else
    PROJECT_ROOT="$(pwd)"
fi

TEMPLATES_DIR="$PROJECT_ROOT/templates"
FRAMEWORKS_DIR="$PROJECT_ROOT/frameworks"
SITES_DIR="$PROJECT_ROOT/sites"
CONFIG_DIR="$PROJECT_ROOT/config"
BACKUPS_DIR="$PROJECT_ROOT/backups"

# =============================================================================
# LOGGING
# =============================================================================
log_info()  { echo -e "${BLUE}i${NC}  $1"; }
log_ok()    { echo -e "${GREEN}✓${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}!${NC}  $1"; }
log_error() { echo -e "${RED}✗${NC}  $1" >&2; }

# =============================================================================
# UTILITAIRES
# =============================================================================

# Sed cross-platform (macOS vs Linux)
sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Génération de mot de passe aléatoire
generate_password() {
    local length="${1:-32}"
    # Utilise /dev/urandom avec base64, supprime les caractères spéciaux
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# =============================================================================
# VALIDATION
# =============================================================================

# Validation nom de site (alphanum + tirets, commence/finit par alphanum)
validate_site_name() {
    local name="$1"

    # Vérification caractères autorisés
    if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        log_error "Nom invalide: '$name'"
        log_error "Utilisez uniquement: lettres minuscules, chiffres, tirets"
        log_error "Doit commencer et finir par une lettre ou un chiffre"
        return 1
    fi

    # Longueur max 63 (limite DNS/Docker)
    if [[ ${#name} -gt 63 ]]; then
        log_error "Nom trop long: ${#name} caractères (max 63)"
        return 1
    fi

    # Longueur min 2
    if [[ ${#name} -lt 2 ]]; then
        log_error "Nom trop court: ${#name} caractère (min 2)"
        return 1
    fi

    return 0
}

# Validation URL/domaine
validate_url() {
    local url="$1"

    # Accepte: domain.tld, sub.domain.tld, localhost, localhost:port
    if [[ ! "$url" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(:[0-9]+)?$ ]]; then
        log_error "URL invalide: '$url'"
        log_error "Format attendu: domain.com, sub.domain.com ou localhost:3000"
        return 1
    fi

    return 0
}

# Validation nom de template
validate_template_name() {
    local name="$1"

    if [[ ! -d "$TEMPLATES_DIR/$name" ]]; then
        log_error "Template inexistant: '$name'"
        log_info "Templates disponibles:"
        ls -1 "$TEMPLATES_DIR" 2>/dev/null | sed 's/^/  - /'
        return 1
    fi

    return 0
}

# =============================================================================
# INTERACTIONS UTILISATEUR
# =============================================================================

# Confirmation interactive
confirm() {
    local message="${1:-Continuer ?}"
    local default="${2:-n}"  # n = non par défaut

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -p "$(echo -e "${YELLOW}?${NC}  $message $prompt ")" -n 1 -r
    echo

    if [[ -z "$REPLY" ]]; then
        [[ "$default" == "y" ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Demande une valeur à l'utilisateur
prompt_value() {
    local message="$1"
    local default="${2:-}"
    local result

    if [[ -n "$default" ]]; then
        read -p "$(echo -e "${YELLOW}?${NC}  $message [$default]: ")" result
        echo "${result:-$default}"
    else
        read -p "$(echo -e "${YELLOW}?${NC}  $message: ")" result
        echo "$result"
    fi
}

# =============================================================================
# VÉRIFICATIONS DOCKER
# =============================================================================

# Vérifie que Docker est installé et accessible
require_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker n'est pas installé"
        log_info "Installez Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon n'est pas accessible"
        log_info "Essayez avec sudo ou vérifiez que Docker est démarré"
        exit 1
    fi
}

# Vérifie que le réseau 'web' existe
require_web_network() {
    if ! docker network ls --format '{{.Name}}' | grep -q "^web$"; then
        log_error "Le réseau Docker 'web' n'existe pas"
        log_info "Créez-le avec: sudo docker network create web"
        exit 1
    fi
}

# Crée le réseau 'web' s'il n'existe pas
ensure_web_network() {
    if ! docker network ls --format '{{.Name}}' | grep -q "^web$"; then
        log_info "Création du réseau Docker 'web'..."
        docker network create web
        log_ok "Réseau 'web' créé"
    fi
}

# =============================================================================
# GESTION DES ERREURS
# =============================================================================

# Variable pour stocker le dossier à nettoyer en cas d'erreur
_CLEANUP_DIR=""

# Fonction de nettoyage appelée en cas d'erreur
_cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && -n "$_CLEANUP_DIR" && -d "$_CLEANUP_DIR" ]]; then
        log_warn "Nettoyage suite à erreur..."
        rm -rf "$_CLEANUP_DIR"
    fi
    exit $exit_code
}

# Active le nettoyage automatique pour un dossier
set_cleanup_dir() {
    _CLEANUP_DIR="$1"
    trap _cleanup_on_error EXIT
}

# Désactive le nettoyage (à appeler après succès)
clear_cleanup_dir() {
    _CLEANUP_DIR=""
    trap - EXIT
}

# =============================================================================
# AFFICHAGE
# =============================================================================

# Affiche un titre de section
print_header() {
    local title="$1"
    echo ""
    echo -e "${BLUE}=== $title ===${NC}"
    echo ""
}

# Affiche la liste des templates disponibles
list_templates() {
    log_info "Templates disponibles:"
    for template in "$TEMPLATES_DIR"/*/; do
        if [[ -d "$template" ]]; then
            echo "  - $(basename "$template")"
        fi
    done
}

# Affiche la liste des sites existants
list_sites() {
    log_info "Sites existants:"
    local count=0
    for site in "$SITES_DIR"/*/; do
        if [[ -d "$site" && "$(basename "$site")" != ".gitkeep" ]]; then
            echo "  - $(basename "$site")"
            ((count++)) || true
        fi
    done
    if [[ $count -eq 0 ]]; then
        echo "  (aucun site)"
    fi
}
