#!/bin/bash
# Lance un container Docker Kasm (bureau Linux XFCE4 + noVNC) pour un étudiant.
# Usage: bash lancer_kasm.sh <username> <groups> <tp_name> <annee_univ> <niveau> <sous_groupe>
# Chemin de déploiement: /home/docker/authentik/lancer_kasm.sh

USER_NAME=$1
GROUPS_RAW=$2
TP_NAME=$3
ANNEE_UNIV=$4
NIVEAU=$5
SOUS_GROUPE=$6

[ -z "$ANNEE_UNIV" ]  && ANNEE_UNIV="25-26"
[ -z "$TP_NAME" ]     && TP_NAME="desktop"
[ -z "$NIVEAU" ]      && NIVEAU="L1"
[ -z "$SOUS_GROUPE" ] && SOUS_GROUPE=""

PREMIER_GROUPE=$(echo "$GROUPS_RAW" | cut -d',' -f1)
IMAGE="moubarakyampa/issatmh-${TP_NAME}"
CONTAINER_NAME="${TP_NAME}-${USER_NAME}-${ANNEE_UNIV}"

# --- Nettoyage: supprimer les confs nginx avec port vide (invalides) ---
for _conf in /etc/nginx/kasm-locations/*.conf; do
    [ -f "$_conf" ] || continue
    if grep -qE 'proxy_pass http://127\.0\.0\.1:/' "$_conf"; then
        echo "==> Suppression conf invalide (port vide): $_conf"
        sudo rm -f "$_conf"
    fi
done

# --- Auto-repair: créer les confs manquantes pour les containers kasm actifs ---
for _cname in $(docker ps --filter "label=app=kasm" --filter "status=running" --format "{{.Names}}"); do
    _cconf="/etc/nginx/kasm-locations/${_cname}.conf"
    [ -f "$_cconf" ] && continue
    _cport=$(docker inspect "$_cname" \
        --format '{{(index (index .NetworkSettings.Ports "6901/tcp") 0).HostPort}}' 2>/dev/null)
    [ -z "$_cport" ] && continue
    echo "==> Création conf manquante: $_cname (port $_cport)"
    sudo tee "$_cconf" > /dev/null << AUTOCONF
location = /kasm/${_cname}/ {
    return 302 /kasm/${_cname}/vnc_auto.html?autoconnect=true&reconnect=true&reconnect_delay=1000&resize=scale&quality=6&path=kasm/${_cname}/websockify;
}
location ^~ /kasm/${_cname}/websockify {
    proxy_pass http://127.0.0.1:${_cport}/websockify;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_read_timeout 3600;
    proxy_send_timeout 3600;
    proxy_buffering off;
}
location ^~ /kasm/${_cname}/ {
    proxy_pass http://127.0.0.1:${_cport}/;
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
AUTOCONF
done

echo "==> Lancement TP=$TP_NAME pour $USER_NAME"
echo "==> Image: $IMAGE | Container: $CONTAINER_NAME"

# --- Stopper l'ancien container si différent ---
RUNNING=$(docker ps --filter "name=${USER_NAME}" --filter "status=running" \
          --format "{{.Names}}" | head -1)
if [ -n "$RUNNING" ] && [ "$RUNNING" != "$CONTAINER_NAME" ]; then
    echo "==> Stop ancien container: $RUNNING"
    docker stop "$RUNNING"
    sudo rm -f /etc/nginx/kasm-locations/${RUNNING}.conf
    sudo nginx -t && sudo systemctl reload nginx
fi

# --- Démarrage ou création du container ---
if [ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
    echo "Container existe → restart"
    docker start "$CONTAINER_NAME"
    sleep 3
    PORT=$(docker inspect ${CONTAINER_NAME} \
        --format '{{(index (index .NetworkSettings.Ports "6901/tcp") 0).HostPort}}')
    [ -z "$PORT" ] && echo "ERREUR: port vide après restart" && exit 1
else
    # Créer les dossiers de données persistants
    for DIR in Documents Downloads Music Pictures Videos PDF Uploads Rendu; do
        sudo mkdir -p "/home/docker/kasm-data/$USER_NAME/$DIR"
    done
    sudo chown -R 1000:1000 "/home/docker/kasm-data/$USER_NAME"
    sudo chmod -R 755 "/home/docker/kasm-data/$USER_NAME"

    # Trouver un port libre entre 7000 et 8000
    for PORT in $(seq 7000 8000); do
        USED=$(ss -Htan | awk '{print $4}' | grep -oE '[0-9]+$' | grep -xF "$PORT")
        DOCKER_USED=$(docker inspect $(docker ps -aq) \
            --format '{{json .HostConfig.PortBindings}}' 2>/dev/null \
            | grep -oE 'HostPort":"[0-9]+' | grep -oE '[0-9]+$' | grep -xF "$PORT")
        if [ -z "$USED" ] && [ -z "$DOCKER_USED" ]; then break; fi
        PORT=""
    done
    [ -z "$PORT" ] && echo "ERREUR: aucun port libre" && exit 1

    echo "Port: $PORT"

    docker run -d \
        --security-opt seccomp=unconfined \
        --shm-size="600m" \
        --memory="10g" \
        --restart=no \
        -p "$PORT:6901" \
        -v "/home/docker/kasm-data/$USER_NAME/Documents:/home/etudiant/Documents" \
        -v "/home/docker/kasm-data/$USER_NAME/Downloads:/home/etudiant/Downloads" \
        -v "/home/docker/kasm-data/$USER_NAME/Music:/home/etudiant/Music" \
        -v "/home/docker/kasm-data/$USER_NAME/Pictures:/home/etudiant/Pictures" \
        -v "/home/docker/kasm-data/$USER_NAME/Videos:/home/etudiant/Videos" \
        -v "/home/docker/kasm-data/$USER_NAME/PDF:/home/etudiant/PDF" \
        -v "/home/docker/kasm-data/$USER_NAME/Uploads:/home/etudiant/Uploads" \
        -v "/home/docker/kasm-data/$USER_NAME/Rendu:/home/etudiant/Rendu" \
        -e ETUDIANT_USERNAME="$USER_NAME" \
        -e TP_TYPE="$TP_NAME" \
        -e ANNEE_UNIV="$ANNEE_UNIV" \
        --add-host n8n.issat.local:172.17.0.1 \
        --add-host dash.issat.local:172.17.0.1 \
        --add-host labo.issat.local:172.17.0.1 \
        --name "$CONTAINER_NAME" \
        --label app=kasm \
        --label etudiant="$USER_NAME" \
        --label tp="$TP_NAME" \
        --label groupe="$PREMIER_GROUPE" \
        --label groupes="$GROUPS_RAW" \
        --label annee_univ="$ANNEE_UNIV" \
        --label niveau="$NIVEAU" \
        --label sous_groupe="$SOUS_GROUPE" \
        "$IMAGE"

    sleep 3
    PORT=$(docker inspect ${CONTAINER_NAME} \
        --format '{{(index (index .NetworkSettings.Ports "6901/tcp") 0).HostPort}}')
fi

[ -z "$PORT" ] && echo "ERREUR: impossible de lire le port" && exit 1

# --- Génération config Nginx ---
sudo mkdir -p /etc/nginx/kasm-locations
sudo tee /etc/nginx/kasm-locations/${CONTAINER_NAME}.conf > /dev/null << NGINX
location = /kasm/${CONTAINER_NAME}/ {
    return 302 /kasm/${CONTAINER_NAME}/vnc_auto.html?autoconnect=true&reconnect=true&reconnect_delay=1000&resize=scale&quality=6&path=kasm/${CONTAINER_NAME}/websockify;
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
