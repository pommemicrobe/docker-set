# Roadmap

Liste des fonctionnalités prévues pour docker-set.

## Gestion des sites

- [ ] **Site clone** : Dupliquer un site existant avec sa configuration
- [ ] **Site migrate** : Déplacer un site vers un autre serveur
- [ ] **Site status** : Vue d'ensemble de tous les sites (état, ressources, URLs)

## Backups

- [ ] **site-backup.sh** : Sauvegarde des fichiers app + base de données
- [ ] **site-restore.sh** : Restauration depuis une sauvegarde
- [ ] Backups automatiques programmés (cron)
- [ ] Rotation des backups (garder les N derniers)

## Logs et monitoring

- [ ] **Logs centralisés** : Accès facile aux logs de tous les sites
- [ ] **Health monitoring** : Dashboard simple pour voir l'état des containers
- [ ] Alertes en cas de container down

## SSL et sécurité

- [ ] **SSL staging** : Option Let's Encrypt staging pour éviter les rate limits
- [ ] **Wildcard SSL** : Support des certificats wildcard pour sous-domaines
- [ ] **Basic auth** : Protection par mot de passe d'un site

## Maintenance

- [ ] **Auto-update** : Mise à jour des images Docker de base
- [ ] **Cleanup** : Nettoyage des images/volumes Docker inutilisés

## Idées futures

- Support de templates personnalisés (user-defined)
- Interface web d'administration
- Intégration CI/CD (deploy via webhook)
- Support PostgreSQL en plus de MySQL
- Support Redis/Memcached pour le cache
- Reverse proxy vers services externes

---

Les contributions et suggestions sont les bienvenues !
