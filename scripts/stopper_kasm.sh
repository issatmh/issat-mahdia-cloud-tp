#!/bin/bash
# Arrête le container actif d'un étudiant et supprime sa config Nginx.
# Compatible Linux ET Windows (recherche par nom d'étudiant).
# Usage: bash stopper_kasm.sh <username>
# Chemin de déploiement: /home/docker/authentik/stopper_kasm.sh

USER_NAME=$1

CONTAINER=$(docker ps --filter "name=${USER_NAME}" --filter "status=running" \
            --format "{{.Names}}" | head -1)

if [ -n "$CONTAINER" ]; then
    docker stop "$CONTAINER"
    echo "Container $CONTAINER arrêté."
    if [ -f "/etc/nginx/kasm-locations/${CONTAINER}.conf" ]; then
        sudo rm "/etc/nginx/kasm-locations/${CONTAINER}.conf"
        sudo nginx -t && sudo systemctl reload nginx
        echo "Config Nginx supprimée pour $CONTAINER"
    fi
else
    echo "Aucun container actif pour $USER_NAME"
fi

# Note: le volume Windows win-disk-{user}-{annee} est conservé après l'arrêt.
# Windows redémarre normalement à la prochaine connexion sans réinstallation.
