FROM moubarakyampa/issatmh-desktop:latest

# TP Développement Web — HTML/CSS/JS, Node.js, VSCode, npm
# Image publiée: moubarakyampa/issatmh-web:latest

USER root

# Node.js (LTS) via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# VSCode
RUN wget -qO /tmp/vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" \
    && dpkg -i /tmp/vscode.deb || apt-get install -f -y \
    && rm /tmp/vscode.deb

# Outils complémentaires
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

USER 1000
