FROM kasmweb/desktop:1.15.0

# Base ISSAT — bureau XFCE4 en français avec dossiers persistants
# Hérite de Kasm Workspaces (XFCE4 + noVNC + websockify intégrés)

USER root

# Locale française
RUN apt-get update && apt-get install -y \
    language-pack-fr \
    && locale-gen fr_FR.UTF-8 \
    && update-locale LANG=fr_FR.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=fr_FR.UTF-8
ENV LANGUAGE=fr_FR:fr
ENV LC_ALL=fr_FR.UTF-8

# Dossiers montés depuis l'hôte (bind mounts définis dans lancer_kasm.sh)
RUN mkdir -p \
    /home/etudiant/Documents \
    /home/etudiant/Downloads \
    /home/etudiant/Music \
    /home/etudiant/Pictures \
    /home/etudiant/Videos \
    /home/etudiant/PDF \
    /home/etudiant/Uploads \
    /home/etudiant/Rendu \
    && chown -R 1000:1000 /home/etudiant/

USER 1000
