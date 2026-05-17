#!/bin/bash
# Régénère toutes les configs Nginx pour les containers kasm arrêtés.
# Utilisation: en cas de perte des configs (redémarrage serveur, incident).
# Chemin de déploiement: /home/docker/authentik/fix_nginx_configs.sh

echo "Génération des configs Nginx pour tous les containers kasm..."

for container in $(docker ps -a --format '{{.Names}}' | grep ^kasm-); do
    user=$(echo $container | sed 's/kasm-//')

    docker start $container 2>/dev/null
    port=$(docker inspect $container \
        --format '{{(index (index .NetworkSettings.Ports "6901/tcp") 0).HostPort}}' 2>/dev/null)

    if [ -z "$port" ]; then
        echo "  ❌ $user : port non trouvé"
        continue
    fi

    sudo tee /etc/nginx/kasm-locations/kasm-${user}.conf > /dev/null << NGINX
location = /kasm/${user}/ {
    return 302 /kasm/${user}/vnc_auto.html?autoconnect=true&reconnect=true&reconnect_delay=1000&resize=scale&quality=6&path=kasm/${user}/websockify;
}
location ^~ /kasm/${user}/websockify {
    proxy_pass http://127.0.0.1:${port}/websockify;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_read_timeout 3600;
    proxy_send_timeout 3600;
    proxy_buffering off;
}
location ^~ /kasm/${user}/ {
    proxy_pass http://127.0.0.1:${port}/;
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
    echo "  ✅ $user → port $port"
done

sudo nginx -t && sudo systemctl reload nginx
echo "Done !"
