#!/bin/bash
# Lance un container Windows 10 via QEMU/KVM + noVNC pour un étudiant.
# Nécessite /dev/kvm (Intel VT-x ou AMD-V activé dans le BIOS/Proxmox).
# Usage: bash lancer_windows.sh <username> <groups> <tp_name> <annee_univ> <niveau> <sous_groupe>
# Chemin de déploiement: /home/docker/authentik/lancer_windows.sh

USER_NAME=$1
GROUPS_RAW=$2
TP_NAME=$3
ANNEE_UNIV=$4
NIVEAU=$5
SOUS_GROUPE=$6

[ -z "$ANNEE_UNIV" ]  && ANNEE_UNIV="25-26"
[ -z "$TP_NAME" ]     && TP_NAME="windows"
[ -z "$NIVEAU" ]      && NIVEAU="L1"
[ -z "$SOUS_GROUPE" ] && SOUS_GROUPE=""

PREMIER_GROUPE=$(echo "$GROUPS_RAW" | cut -d',' -f1)
IMAGE="moubarakyampa/issatmh-windows:2.0.0"
CONTAINER_NAME="windows-${USER_NAME}-${ANNEE_UNIV}"
VOLUME_NAME="win-disk-${USER_NAME}-${ANNEE_UNIV}"

echo "==> Lancement TP Windows pour $USER_NAME"
echo "==> Image: $IMAGE | Container: $CONTAINER_NAME | Volume: $VOLUME_NAME"

# Vérification KVM obligatoire
if [ ! -e /dev/kvm ]; then
    echo "ERREUR: /dev/kvm absent — activer Intel VT-x dans le BIOS/Proxmox"
    exit 1
fi

# Stopper l'ancien container si différent
RUNNING=$(docker ps --filter "name=${USER_NAME}" --filter "status=running" \
          --format "{{.Names}}" | head -1)
if [ -n "$RUNNING" ] && [ "$RUNNING" != "$CONTAINER_NAME" ]; then
    echo "==> Stop ancien container: $RUNNING"
    docker stop "$RUNNING"
    sudo rm -f /etc/nginx/kasm-locations/${RUNNING}.conf
    sudo nginx -t && sudo systemctl reload nginx
fi

if [ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
    echo "Container existe → restart"
    docker start "$CONTAINER_NAME"
    sleep 5
    PORT=$(docker inspect ${CONTAINER_NAME} \
        --format '{{(index (index .NetworkSettings.Ports "8006/tcp") 0).HostPort}}')
    [ -z "$PORT" ] && echo "ERREUR: port vide après restart" && exit 1
else
    # Trouver un port libre entre 7000 et 8000
    for PORT in $(seq 7000 8000); do
        USED=$(ss -Htan | awk '{print $4}' | grep -oE '[0-9]+$' | grep -xF "$PORT")
        DOCKER_USED=$(docker inspect $(docker ps -aq) \
            --format '{{json .HostConfig.PortBindings}}' 2>/dev/null \
            | grep -oE 'HostPort":"[0-9]+' | grep -oE '[0-9]+$' | grep -xF "$PORT")
        if [ -z "$USED" ] && [ -z "$DOCKER_USED" ]; then break; fi
        PORT=""
    done
    [ -z "$PORT" ] && echo "ERREUR: aucun port libre entre 7000 et 8000" && exit 1

    echo "Port: $PORT"

    docker run -d \
        --privileged \
        --device /dev/kvm \
        --memory="8g" \
        --cpus="4" \
        --restart=no \
        -p "$PORT:8006" \
        -v "$VOLUME_NAME:/storage" \
        -e ETUDIANT_USERNAME="$USER_NAME" \
        -e ANNEE_UNIV="$ANNEE_UNIV" \
        --add-host n8n.issat.local:172.17.0.1 \
        --add-host dash.issat.local:172.17.0.1 \
        --add-host labo.issat.local:172.17.0.1 \
        --name "$CONTAINER_NAME" \
        --label app=kasm \
        --label etudiant="$USER_NAME" \
        --label tp="windows" \
        --label groupe="$PREMIER_GROUPE" \
        --label groupes="$GROUPS_RAW" \
        --label annee_univ="$ANNEE_UNIV" \
        --label niveau="$NIVEAU" \
        --label sous_groupe="$SOUS_GROUPE" \
        "$IMAGE"

    sleep 5
    PORT=$(docker inspect ${CONTAINER_NAME} \
        --format '{{(index (index .NetworkSettings.Ports "8006/tcp") 0).HostPort}}')
fi

[ -z "$PORT" ] && echo "ERREUR: impossible de lire le port" && exit 1

# --- Génération config Nginx ---
# Windows utilise vnc.html (cursor=local) et non vnc_auto.html
sudo mkdir -p /etc/nginx/kasm-locations
sudo tee /etc/nginx/kasm-locations/${CONTAINER_NAME}.conf > /dev/null << NGINX
location = /kasm/${CONTAINER_NAME}/ {
    return 302 /kasm/${CONTAINER_NAME}/vnc.html?autoconnect=true&cursor=local&quality=2&compression=7&resize=scale&path=kasm/${CONTAINER_NAME}/websockify;
}

location ^~ /kasm/${CONTAINER_NAME}/websockify {
    proxy_pass http://127.0.0.1:${PORT}/websockify;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_read_timeout 3600;
    proxy_send_timeout 3600;
    proxy_buffering off;
}

location ^~ /kasm/${CONTAINER_NAME}/ {
    proxy_pass http://127.0.0.1:${PORT}/;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600;
    proxy_send_timeout 3600;
    proxy_buffering off;
}
NGINX

sudo nginx -t && sudo systemctl reload nginx
echo "OK → http://labo.issat.local/kasm/${CONTAINER_NAME}/"
