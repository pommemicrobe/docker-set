#!/usr/bin/env bash
#
# setup.sh - Initialisation de l'infrastructure docker-set
#
# Usage: ./scripts/setup.sh
#

# Charger la bibliothèque commune
source "$(dirname "$0")/../lib/common.sh"

# =============================================================================
# FONCTIONS
# =============================================================================

setup_traefik() {
    print_header "Configuration Traefik"

    local traefik_dir="$CONFIG_DIR/traefik"

    # Vérifier si déjà configuré
    if [[ -f "$traefik_dir/traefik.yaml" && -f "$traefik_dir/acme.json" ]]; then
        log_warn "Traefik semble déjà configuré"
        if ! confirm "Reconfigurer Traefik ?"; then
            return 0
        fi
    fi

    # Copier traefik.yaml.dist
    if [[ ! -f "$traefik_dir/traefik.yaml" ]]; then
        cp "$traefik_dir/traefik.yaml.dist" "$traefik_dir/traefik.yaml"
        log_ok "traefik.yaml créé"
    fi

    # Demander l'email pour Let's Encrypt
    local current_email
    current_email=$(grep -oP 'email:\s*"\K[^"]+' "$traefik_dir/traefik.yaml" 2>/dev/null || echo "ACME_EMAIL")

    if [[ "$current_email" == "ACME_EMAIL" ]]; then
        local email
        email=$(prompt_value "Email pour les certificats SSL (Let's Encrypt)")

        if [[ -z "$email" ]]; then
            log_error "Email requis pour Let's Encrypt"
            exit 1
        fi

        sed_inplace "s|ACME_EMAIL|$email|g" "$traefik_dir/traefik.yaml"
        log_ok "Email configuré: $email"
    else
        log_info "Email actuel: $current_email"
    fi

    # Créer acme.json avec les bonnes permissions
    if [[ ! -f "$traefik_dir/acme.json" ]]; then
        cp "$traefik_dir/acme.json.dist" "$traefik_dir/acme.json"
    fi
    chmod 600 "$traefik_dir/acme.json"
    log_ok "acme.json configuré (permissions 600)"

    # Créer le dossier logs
    mkdir -p "$traefik_dir/logs"
    log_ok "Dossier logs créé"
}

setup_mysql() {
    print_header "Configuration MySQL"

    local mysql_dir="$CONFIG_DIR/mysql"

    # Vérifier si déjà configuré
    if [[ -f "$mysql_dir/.env" ]]; then
        log_warn "MySQL semble déjà configuré"
        if ! confirm "Reconfigurer MySQL ?"; then
            return 0
        fi
    fi

    # Copier .env.dist
    cp "$mysql_dir/.env.dist" "$mysql_dir/.env"

    # Générer ou demander le mot de passe
    local password
    if confirm "Générer un mot de passe sécurisé automatiquement ?" "y"; then
        password=$(generate_password 32)
        log_ok "Mot de passe généré (32 caractères)"
    else
        password=$(prompt_value "Mot de passe root MySQL")
        if [[ -z "$password" ]]; then
            log_error "Mot de passe requis"
            exit 1
        fi
    fi

    sed_inplace "s|GENERATED_PASSWORD|$password|g" "$mysql_dir/.env"
    log_ok "Mot de passe configuré dans .env"

    # Créer le dossier data
    mkdir -p "$mysql_dir/data"
    log_ok "Dossier data créé"

    # Afficher le mot de passe
    echo ""
    log_warn "IMPORTANT: Notez ce mot de passe, il ne sera plus affiché"
    echo "  MYSQL_ROOT_PASSWORD=$password"
    echo ""
}

start_infrastructure() {
    print_header "Démarrage de l'infrastructure"

    # Démarrer Traefik
    log_info "Démarrage de Traefik..."
    (cd "$CONFIG_DIR/traefik" && docker compose up -d)
    log_ok "Traefik démarré"

    # Démarrer MySQL
    log_info "Démarrage de MySQL..."
    (cd "$CONFIG_DIR/mysql" && docker compose up -d)
    log_ok "MySQL démarré"

    # Attendre un peu et vérifier
    sleep 3
    echo ""
    log_info "État des containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "traefik|mysql|NAMES"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    print_header "Setup docker-set"

    # Vérifications préalables
    log_info "Vérification des prérequis..."
    require_docker
    log_ok "Docker disponible"

    # Créer le réseau web si nécessaire
    ensure_web_network

    # Créer les dossiers nécessaires
    mkdir -p "$SITES_DIR" "$BACKUPS_DIR"

    # Configuration Traefik
    setup_traefik

    # Configuration MySQL
    setup_mysql

    # Démarrer ?
    echo ""
    if confirm "Démarrer l'infrastructure maintenant ?" "y"; then
        start_infrastructure
    else
        log_info "Pour démarrer plus tard:"
        echo "  cd $CONFIG_DIR/traefik && sudo docker compose up -d"
        echo "  cd $CONFIG_DIR/mysql && sudo docker compose up -d"
    fi

    # Résumé
    print_header "Setup terminé"
    log_ok "Infrastructure configurée avec succès"
    echo ""
    log_info "Prochaines étapes:"
    echo "  1. Créer un site: ./scripts/site-create.sh <nom> <url> <template>"
    echo "  2. Templates disponibles:"
    ls -1 "$TEMPLATES_DIR" 2>/dev/null | sed 's/^/     - /' || echo "     (aucun template)"
    echo ""
}

main "$@"
