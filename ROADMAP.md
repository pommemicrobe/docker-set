# Roadmap

Objectif : tout gérer avec Docker seul — aucun runtime installé sur l'hôte,
ni en local (dev), ni sur les serveurs (prod).

## Phase 1 — Double mode : dev / prod (en cours)

Chaque site est créé dans un des deux modes, stocké dans `site.yaml` :

- **dev** (défaut) : modèle actuel. Source montée en volume, dépendances
  installées au démarrage, toolchain complète dans l'image. Itération rapide,
  commandes de build via shell dans le conteneur.
- **prod** : image immuable multi-stage. Dépendances et build figés au
  `docker compose build`, runtime minimal (non-root, sans devtools, sans PM2),
  crash = restart policy (fail fast), `init: true`, données persistantes
  (SQLite, uploads) dans un volume nommé monté sur `/app/data`.

Tickets :

- [x] T1 — Socle : `site-create.sh --mode`, manifest, variantes de templates, `.dockerignore`
- [x] T2 — Image prod Go (multi-stage, binaire statique, runtime minimal)
- [x] T3 — Image prod Bun
- [x] T4 — Image prod Node.js (PM2 supprimé en prod)
- [x] T5 — Image prod PHP (composer `--no-dev`, code dans l'image)
- [x] T6 — `site-shell.sh` / `site-run.sh` (commandes dans les conteneurs, zéro install hôte)
- [x] T7 — Déploiement git : `--from-git`, `site-deploy.sh` (git conteneurisé)
- [x] T8 — Bascule de mode via `site-update.sh --mode`, colonne mode dans `site-list.sh`
- [x] T9 — Volume data prod dans backup/restore (SQLite)
- [x] T10 — Tests smoke des deux modes + lint shellcheck via Docker
- [x] T11 — Documentation (README, CLAUDE.md)

## Phase 2 — Control plane

Un petit conteneur API Go (stdlib uniquement) qui `argv`-exec les scripts
whitelistés (jamais de réimplémentation), géré via `scripts/api-setup.sh` :

- [x] Endpoints REST enveloppant les scripts (`/api/sites` list/create,
  `/api/sites/{name}/deploy`, `/api/sites/{name}/logs`, `/api/jobs`) sous auth
  Bearer, jobs asynchrones en mémoire
- [x] Webhook GitHub `/hooks/github/{site}` → `site-deploy.sh` (HMAC SHA-256,
  filtré sur la branche `source_branch` du manifest)
- [x] `scripts/api-setup.sh` : génération de `config/api/.env` (secrets
  aléatoires, chmod 600), build + démarrage, attente de `/health`

Le proxy Docker filtrant (docker-socket-proxy) a été abandonné au profit d'un
binding localhost + scripts whitelistés + auth token/HMAC : la frontière de
sécurité est la surface de l'API, pas le socket (`compose build` + bind mounts
sont de toute façon root-equivalents).

Les scripts restent la seule source de vérité ; l'API ne réimplémente aucune
logique.

## Phase 3 — Interface web

- [x] SPA minimale servie par le control plane : liste des sites avec état
  (auto-refresh), formulaire de création (alimenté par `GET /api/meta`), bouton
  deploy, streaming des logs et de la sortie des jobs. JS vanilla embarqué dans
  le binaire Go (`//go:embed`, aucune étape de build, aucun framework/CDN) ;
  assets statiques non authentifiés, token en `sessionStorage`, CSP stricte. La
  sortie des jobs est désormais nettoyée des codes couleur ANSI (rendu propre en
  curl comme dans l'UI).

L'observabilité reste sur étagère (Dozzle, Uptime Kuma) — pas redéveloppée ici.

## Gestion des sites

- [x] **site-list.sh** : vue d'ensemble de tous les sites (état, ressources, URLs)
- [x] **site-update.sh** : mise à jour d'un site (rebuild image de base, version runtime, ressources, `--all`)
- [ ] **Site clone** : dupliquer un site existant avec sa configuration
- [ ] **Site migrate** : déplacer un site vers un autre serveur

## Backups

- [x] **site-backup.sh** : sauvegarde des fichiers app + base de données
- [x] **site-restore.sh** : restauration depuis une sauvegarde
- [ ] Backups automatiques programmés (cron)
- [ ] Rotation des backups (garder les N derniers)

## SSL et sécurité

- [ ] **SSL staging** : option Let's Encrypt staging pour éviter les rate limits
- [ ] **Wildcard SSL** : certificats wildcard pour sous-domaines
- [ ] **Basic auth** : protection par mot de passe d'un site

## Dette connue

- Les conteneurs en mode dev tournent en root (l'utilisateur `app` existe
  dans les images mais `USER` n'est jamais appliqué) ; le mode prod corrige,
  le mode dev nécessitera une stratégie de mapping UID.
- `init: true` bénéficierait aussi au mode dev (signaux à travers les
  wrappers `sh -c` de démarrage).
- Laravel en prod nécessite un volume `storage/` en plus de la convention
  `/app/data` (documenté, non automatisé).
- Le conteneur API tourne en root (socket Docker + écritures dans le repo) ;
  les sites créés via l'API appartiennent donc à root sur un hôte Linux.

## Idées futures

- Templates personnalisés (user-defined)
- Support PostgreSQL en plus de MySQL
- Support Redis/Memcached pour le cache
- Reverse proxy vers services externes

## Non-objectifs

Multi-serveur, multi-utilisateur, registry privé, zero-downtime, monitoring
custom. Si l'un devient nécessaire : passer à un PaaS sur étagère
(Dokploy/Coolify) plutôt que le développer ici.
