# Diagrammes — Mini-Cloud Pédagogique ISSAT Mahdia

> Tous les diagrammes sont au format [Mermaid](https://mermaid.js.org/) et s'affichent automatiquement sur GitHub.
> **Les adresses IP sont fictives** — elles servent uniquement d'illustration (`10.0.x.x` / `10.1.x.x`).

---

## Table des matières

1. [Diagramme de Gantt](#1-diagramme-de-gantt)
2. [Architecture réseau globale](#2-architecture-réseau-globale)
3. [Architecture des réseaux Docker](#3-architecture-des-réseaux-docker)
4. [VM vs Conteneurs Docker](#4-vm-vs-conteneurs-docker)
5. [Cas d'utilisation — Général](#5-cas-dutilisation--général)
6. [Cas d'utilisation — Étudiant](#6-cas-dutilisation--étudiant)
7. [Cas d'utilisation — Enseignant](#7-cas-dutilisation--enseignant)
8. [Cas d'utilisation — Administrateur](#8-cas-dutilisation--administrateur)
9. [Diagramme de séquence — Session étudiant](#9-diagramme-de-séquence--flux-complet-session-étudiant)
10. [Hiérarchie des images Docker](#10-hiérarchie-des-images-docker)
11. [Organigramme — lancer\_issat.sh](#11-organigramme--lancer_issatsh)
12. [Flux de soumission — n8n](#12-flux-de-soumission--n8n)

---

## 1. Diagramme de Gantt

> Période : **06 Février 2026 → 20 Mai 2026** — 8 sprints Scrum — durée totale : 15 semaines

```mermaid
gantt
    title Diagramme de Gantt — Plateforme Mini-Cloud ISSAT Mahdia (06 Fev - 20 Mai 2026)
    dateFormat  YYYY-MM-DD
    axisFormat  %d %b

    section Sprint 1
    Recherche et veille technologique           :done, s1, 2026-02-06, 14d

    section Sprint 2
    Audit de l environnement existant           :done, s2, after s1, 7d

    section Sprint 3
    Elaboration du cahier des charges           :done, s3, after s2, 7d

    section Sprint 4
    Architecture de la solution                 :done, s4, after s3, 14d

    section Sprint 5
    Provisionnement de l infrastructure         :done, s5, after s4, 14d

    section Sprint 6
    Configuration des briques applicatives      :done, s6, after s5, 21d

    section Sprint 7
    Phase d integration et de validation        :done, s7, after s6, 14d

    section Sprint 8
    Mise en production et livraison             :done, s8, after s7, 13d

    section Jalons
    Soutenance                                  :milestone, m1, 2026-05-20, 0d
```

---

## 2. Architecture réseau globale

> **IPs fictives** : réseau ISSAT `10.0.0.0/24` · réseau laboratoire privé `10.1.0.0/24`

```mermaid
graph TB
    classDef student fill:#E3F2FD,stroke:#1565C0,color:#0D47A1,font-weight:bold
    classDef firewall fill:#FFF3E0,stroke:#E65100,color:#BF360C,font-weight:bold
    classDef server fill:#E8F5E9,stroke:#2E7D32,color:#1B5E20
    classDef service fill:#F3E5F5,stroke:#7B1FA2,color:#4A148C
    classDef container fill:#E0F7FA,stroke:#006064,color:#004D40
    classDef flask fill:#FFF8E1,stroke:#F9A825,color:#F57F17

    subgraph ISSAT["Réseau ISSAT  —  10.0.0.0/24"]
        ETU["Postes Etudiants\n10.0.0.x  DHCP"]:::student
        ENS["Postes Enseignants\n10.0.0.x  DHCP"]:::student
    end

    subgraph PFS["pfSense  —  Pare-feu / Routeur / DNS Unbound"]
        WAN["WAN  :  10.0.0.50\nInterface reseau ISSAT"]:::firewall
        LAN["LAN  :  10.1.0.1\nGateway reseau labo"]:::firewall
    end

    subgraph PROX["Proxmox VE  —  Hyperviseur"]
        subgraph UBU["Ubuntu Server  —  10.1.0.10"]
            NGINX["Nginx\nReverse Proxy  :80"]:::service
            AUTH["Authentik\nSSO / OIDC  :9000"]:::service
            VIGIE["Vigie\nMonitoring  :5000"]:::service
            N8N["n8n\nAutomatisation  :5678"]:::service
            FLASKW["webhook_receiver.py\n:9001"]:::flask
            FLASKR["redirector.py\n:8080"]:::flask
            subgraph DOCKER["Conteneurs Docker  —  Ports :7000 - :8000"]
                C1["Container Linux A\nXFCE4 + noVNC"]:::container
                C2["Container Linux B\nXFCE4 + noVNC"]:::container
                C3["Container Windows\nQEMU/KVM + noVNC"]:::container
            end
        end
    end

    ETU -->|"HTTP navigateur"| WAN
    ENS -->|"HTTP navigateur"| WAN
    WAN -->|"NAT + Routage"| LAN
    LAN --> NGINX
    NGINX -->|"issat.local"| AUTH
    NGINX -->|"dash.issat.local"| VIGIE
    NGINX -->|"n8n.issat.local"| N8N
    NGINX -->|"labo.issat.local/user"| DOCKER
    NGINX -->|"auth_request"| FLASKR
    FLASKR -->|"API verif identite"| AUTH
    AUTH -->|"Webhook connexion/deconnexion"| FLASKW
    FLASKW -->|"lancer / stopper containers"| DOCKER
```

---

## 3. Architecture des réseaux Docker

```mermaid
graph LR
    classDef proxy fill:#FFF3E0,stroke:#E65100,color:#BF360C,font-weight:bold
    classDef cont fill:#E0F7FA,stroke:#006064,color:#004D40
    classDef svc fill:#F3E5F5,stroke:#7B1FA2,color:#4A148C
    classDef db fill:#E8F5E9,stroke:#2E7D32,color:#1B5E20
    classDef netlabel fill:#E3F2FD,stroke:#1565C0,color:#0D47A1,font-weight:bold

    NGINX["Nginx\nReseau hote  :80"]:::proxy

    subgraph NET1["docker0  —  172.17.0.0/16  —  Conteneurs etudiants"]
        C1["Etudiant A\nnoVNC :7000"]:::cont
        C2["Etudiant B\nnoVNC :7001"]:::cont
        C3["Etudiant C\nnoVNC :7002"]:::cont
    end

    subgraph NET2["ubuntu_default  —  172.18.0.0/16  —  Stack Authentik"]
        AS["Authentik Server\n:9000 / :9443"]:::svc
        ADB["PostgreSQL\n:5432"]:::db
        ARED["Redis\n:6379"]:::db
    end

    subgraph NET3["vigie-net  —  172.19.0.0/16  —  Stack Vigie"]
        VA["Vigie App\n:5000"]:::svc
        VDB["Vigie DB\n:5433"]:::db
    end

    NGINX <-->|"proxy_pass"| NET1
    NGINX <-->|"proxy_pass"| NET2
    NGINX <-->|"proxy_pass"| NET3
    AS --- ADB
    AS --- ARED
    VA --- VDB
```

---

## 4. VM vs Conteneurs Docker

```mermaid
graph TB
    classDef vmbox fill:#FFEBEE,stroke:#C62828,color:#B71C1C,font-weight:bold
    classDef dkbox fill:#E8F5E9,stroke:#2E7D32,color:#1B5E20,font-weight:bold
    classDef infra fill:#ECEFF1,stroke:#546E7A,color:#263238
    classDef title fill:#E3F2FD,stroke:#1565C0,color:#0D47A1,font-weight:bold
    classDef comp fill:#FFF8E1,stroke:#F9A825,color:#E65100,font-weight:bold

    subgraph VM_ARCH["Architecture — Machines Virtuelles"]
        VT["Machine Virtuelle"]:::title
        VM1["App A\nBins/Libs\nOS Invite"]:::vmbox
        VM2["App B\nBins/Libs\nOS Invite"]:::vmbox
        VM3["App C\nBins/Libs\nOS Invite"]:::vmbox
        HYP["Hyperviseur  VMware / KVM"]:::infra
        VOS["Systeme exploitation hote"]:::infra
        VHW["Infrastructure physique"]:::infra
        VM1 & VM2 & VM3 --> HYP --> VOS --> VHW
    end

    subgraph DK_ARCH["Architecture — Conteneurs Docker"]
        DT["Conteneur Docker"]:::title
        D1["App A\nBins/Libs"]:::dkbox
        D2["App B\nBins/Libs"]:::dkbox
        D3["App C\nBins/Libs"]:::dkbox
        DENG["Docker Engine"]:::infra
        DOS["Systeme exploitation hote"]:::infra
        DHW["Infrastructure physique"]:::infra
        D1 & D2 & D3 --> DENG --> DOS --> DHW
    end

    VM_ARCH -.->|"Demarrage : minutes\nTaille : plusieurs Go\nIsolation : totale OS dedie\nDensite : 5-20 VM/serveur"| CMP
    DK_ARCH -.->|"Demarrage : secondes\nTaille : quelques Mo\nIsolation : partielle kernel partage\nDensite : 50-100+ conteneurs/serveur"| CMP

    CMP["Comparaison"]:::comp
```

---

## 5. Cas d'utilisation — Général

```mermaid
graph LR
    classDef actor fill:#E3F2FD,stroke:#1565C0,color:#0D47A1,font-weight:bold
    classDef secondary fill:#FFF8E1,stroke:#F57F17,color:#E65100,font-weight:bold
    classDef ucetu fill:#F3E5F5,stroke:#7B1FA2,color:#4A148C
    classDef ucens fill:#E8F5E9,stroke:#388E3C,color:#1B5E20
    classDef ucadm fill:#FCE4EC,stroke:#C62828,color:#880E4F

    ETU(["Etudiant"]):::actor
    ENS(["Enseignant"]):::actor
    ADM(["Administrateur"]):::actor
    AUTH(["Authentik\nSSO"]):::secondary
    DOCK(["Docker Engine"]):::secondary

    subgraph SYS["Systeme VDI  —  ISSAT Mahdia"]
        UC1(["S authentifier SSO"]):::ucetu
        UC2(["Consulter les TPs"]):::ucetu
        UC3(["Lancer un TP"]):::ucetu
        UC4(["Travailler sur le bureau"]):::ucetu
        UC5(["Se deconnecter"]):::ucetu
        UC6(["Gerer les seances TP"]):::ucens
        UC7(["Surveiller les ecrans"]):::ucens
        UC8(["Gerer les presences"]):::ucens
        UC9(["Exporter les rapports CSV"]):::ucens
        UC10(["Configurer Authentik"]):::ucadm
        UC11(["Importer etudiants CSV"]):::ucadm
        UC12(["Gerer les images Docker"]):::ucadm
        UC13(["Surveiller l infrastructure"]):::ucadm
    end

    ETU --- UC1 & UC2 & UC3 & UC4 & UC5
    ENS --- UC1 & UC6 & UC7 & UC8 & UC9
    ADM --- UC1 & UC10 & UC11 & UC12 & UC13
    AUTH -.- UC1 & UC10
    DOCK -.- UC3 & UC4 & UC7 & UC12 & UC13
```

---

## 6. Cas d'utilisation — Étudiant

```mermaid
graph LR
    classDef actor fill:#E3F2FD,stroke:#1565C0,color:#0D47A1,font-weight:bold
    classDef secondary fill:#FFF8E1,stroke:#F57F17,color:#E65100,font-weight:bold
    classDef uc fill:#F3E5F5,stroke:#7B1FA2,color:#4A148C
    classDef ucincl fill:#E0F7FA,stroke:#006064,color:#004D40,font-style:italic

    ETU(["Etudiant"]):::actor
    AUTH(["Authentik\nSSO"]):::secondary
    DOCK(["Docker Engine"]):::secondary

    subgraph SYS["Systeme VDI"]
        UC1(["S authentifier SSO"]):::uc
        UC2(["Consulter la liste des TPs"]):::uc
        UC3(["Lancer un TP"]):::uc
        UC3I(["include  Demarrer un container"]):::ucincl
        UC4(["Travailler sur le bureau virtuel"]):::uc
        UC4I(["include  Acceder via noVNC"]):::ucincl
        UC5(["Se deconnecter"]):::uc
    end

    ETU --- UC1 & UC2 & UC3 & UC4 & UC5
    UC3 -.->|"include"| UC3I
    UC4 -.->|"include"| UC4I
    AUTH -.- UC1
    DOCK -.- UC3I & UC4I
```

---

## 7. Cas d'utilisation — Enseignant

```mermaid
graph LR
    classDef actor fill:#E8F5E9,stroke:#2E7D32,color:#1B5E20,font-weight:bold
    classDef secondary fill:#FFF8E1,stroke:#F57F17,color:#E65100,font-weight:bold
    classDef uc fill:#F3E5F5,stroke:#7B1FA2,color:#4A148C
    classDef ucext fill:#E0F7FA,stroke:#006064,color:#004D40,font-style:italic
    classDef ucincl fill:#FFF3E0,stroke:#E65100,color:#BF360C,font-style:italic

    ENS(["Enseignant"]):::actor
    AUTH(["Authentik"]):::secondary
    DOCK(["Docker Engine"]):::secondary

    subgraph SYS["Systeme VDI"]
        UC1(["S authentifier"]):::uc
        UC2(["Gerer les seances de TP"]):::uc
        UC2E1(["extend  Creer une seance"]):::ucext
        UC2E2(["extend  Modifier une seance"]):::ucext
        UC2E3(["extend  Supprimer une seance"]):::ucext
        UC3(["Lancer un TP pour un etudiant"]):::uc
        UC4(["Lancer un TP pour la classe"]):::uc
        UC5(["Surveiller les ecrans\nVue Examen"]):::uc
        UC6(["Gerer les presences"]):::uc
        UC6I1(["include  Marquage manuel"]):::ucincl
        UC6I2(["include  Detection automatique"]):::ucincl
        UC7(["Creer des groupes d etudiants"]):::uc
        UC8(["Acceder au bureau d un etudiant"]):::uc
        UC9(["Exporter les presences CSV"]):::uc
    end

    ENS --- UC1 & UC2 & UC3 & UC4 & UC5 & UC6 & UC7 & UC8 & UC9
    UC2 -.->|"extend"| UC2E1 & UC2E2 & UC2E3
    UC6 -.->|"include"| UC6I1 & UC6I2
    AUTH -.- UC1
    DOCK -.- UC3 & UC4 & UC5 & UC8
```

---

## 8. Cas d'utilisation — Administrateur

```mermaid
graph LR
    classDef actor fill:#FCE4EC,stroke:#880E4F,color:#880E4F,font-weight:bold
    classDef actorinher fill:#E8F5E9,stroke:#2E7D32,color:#1B5E20,font-weight:bold
    classDef secondary fill:#FFF8E1,stroke:#F57F17,color:#E65100,font-weight:bold
    classDef uc fill:#F3E5F5,stroke:#7B1FA2,color:#4A148C
    classDef ucinh fill:#E8EAF6,stroke:#3949AB,color:#1A237E,font-style:italic

    ADM(["Administrateur"]):::actor
    ENS(["Enseignant\nheritage"]):::actorinher
    AUTH(["Authentik"]):::secondary
    DOCK(["Docker Engine"]):::secondary

    subgraph SYS["Systeme VDI"]
        UC1(["S authentifier"]):::uc
        UC2(["Configurer Authentik"]):::uc
        UC3(["Importer etudiants CSV"]):::uc
        UC4(["Gerer les groupes Authentik"]):::uc
        UC5(["Configurer les apps TP"]):::uc
        UC6(["Gerer les comptes utilisateurs"]):::uc
        UC7(["Gerer les noeuds Docker"]):::uc
        UC8(["Gerer les images Docker"]):::uc
        UC9(["Configurer parametres globaux"]):::uc
        UC10(["Consulter le journal d audit"]):::uc
        UC11(["Gerer les alertes"]):::uc
        UC12(["Surveiller l infrastructure"]):::uc
        UCINH(["Heritage  tous les cas Enseignant"]):::ucinh
    end

    ADM --- UC1 & UC2 & UC3 & UC4 & UC5 & UC6 & UC7 & UC8 & UC9 & UC10 & UC11 & UC12
    ADM -->|"extends"| ENS
    ENS --- UCINH
    AUTH -.- UC2 & UC3 & UC4 & UC6
    DOCK -.- UC7 & UC8 & UC12
```

---

## 9. Diagramme de séquence — Flux complet session étudiant

```mermaid
sequenceDiagram
    actor Etudiant
    participant NAV as Navigateur
    participant NGX as Nginx
    participant AUTH as Authentik SSO
    participant RDR as redirector.py
    participant WHK as webhook_receiver.py
    participant DOC as Docker Engine
    participant VIG as Vigie

    Etudiant->>NAV: Accede a labo.issat.local
    NAV->>NGX: GET /
    NGX->>AUTH: Redirection login OIDC
    AUTH-->>Etudiant: Page de connexion SSO
    Etudiant->>AUTH: Identifiant + mot de passe
    AUTH-->>AUTH: Verification credentials
    AUTH-->>NAV: Token OAuth2 + cookie session

    Note over NAV,NGX: Selection du TP

    NAV->>NGX: GET /tp-reseau avec cookie
    NGX->>RDR: auth_request verification identite
    RDR->>AUTH: API info utilisateur
    AUTH-->>RDR: Identite + groupes confirmes
    RDR-->>NGX: 200 OK acces autorise

    Note over WHK,DOC: Lancement automatique du container

    AUTH-)WHK: Webhook evenement connexion
    WHK->>DOC: lancer_issat.sh username tp-reseau
    DOC-->>WHK: Container demarre port noVNC 7042
    WHK->>NGX: Genere conf proxy /username/
    NGX-->>NGX: nginx -s reload

    NGX-->>NAV: Proxy vers noVNC port 7042
    NAV-->>Etudiant: Bureau Linux XFCE4 dans le navigateur

    VIG->>DOC: Detection container labels Docker
    VIG-->>VIG: Marque etudiant present

    Note over Etudiant,VIG: Travail sur le TP — session active

    Etudiant->>AUTH: Deconnexion logout
    AUTH-)WHK: Webhook evenement deconnexion
    WHK->>DOC: stopper_kasm.sh username
    DOC-->>WHK: Container arrete ressources liberees
    WHK->>NGX: Supprime conf proxy /username/
    NGX-->>NGX: nginx -s reload
    VIG-->>VIG: Marque etudiant absent
```

---

## 10. Hiérarchie des images Docker

```mermaid
graph TB
    classDef base fill:#E3F2FD,stroke:#1565C0,color:#0D47A1,font-weight:bold
    classDef mid fill:#E8F5E9,stroke:#2E7D32,color:#1B5E20,font-weight:bold
    classDef tp fill:#F3E5F5,stroke:#7B1FA2,color:#4A148C
    classDef win fill:#FFF3E0,stroke:#E65100,color:#BF360C,font-weight:bold

    BASE["issat/base\nUbuntu 22.04 + XFCE4 + noVNC\nFirefox  VSCode  outils communs"]:::base

    LBASE["issat/linux-base\nHeritage base + libs partagees\nCompatible toutes filieres Linux"]:::mid
    WBASE["issat/windows-base\nQEMU/KVM + noVNC\nWindows via emulation"]:::win

    TIC["issat/tp-tic\nCompilateurs  Wireshark\nCisco Packet Tracer  Git"]:::tp
    IAIO["issat/tp-iaio\nPython 3  TensorFlow\nJupyter  Arduino IDE"]:::tp
    EEA["issat/tp-eea\nLTspice  Proteus\nSimulateurs circuits electroniques"]:::tp
    BIO["issat/tp-bio\nR  BioPython\nOutils bioinformatique"]:::tp
    MAT["issat/tp-mat\nSciPy  GNU Octave\nOutils physique materiaux"]:::tp
    WINTP["issat/tp-windows\nWindows 10\nApplications Windows natives"]:::win

    BASE --> LBASE
    BASE --> WBASE
    LBASE --> TIC
    LBASE --> IAIO
    LBASE --> EEA
    LBASE --> BIO
    LBASE --> MAT
    WBASE --> WINTP
```

---

## 11. Organigramme — lancer_issat.sh

```mermaid
flowchart TD
    classDef startend fill:#1565C0,stroke:#0D47A1,color:white,font-weight:bold
    classDef decision fill:#F57F17,stroke:#E65100,color:#BF360C,font-weight:bold
    classDef action fill:#F3E5F5,stroke:#7B1FA2,color:#4A148C
    classDef error fill:#FFEBEE,stroke:#C62828,color:#B71C1C,font-weight:bold
    classDef success fill:#E8F5E9,stroke:#2E7D32,color:#1B5E20,font-weight:bold

    A([Debut  lancer_issat.sh\nArguments  username  tp-slug]):::startend

    B{Container deja\nactif pour cet user ?}:::decision
    C[Stopper le container existant\nstopper_kasm.sh username]:::action

    D[Selectionner l image Docker\nissat/tp-slug]:::action

    E{Image disponible\nlocalement ?}:::decision
    F[Telecharger l image\ndocker pull issat/tp-slug]:::action

    G[Creer ou verifier le volume\n/data/users/username]:::action

    H[Lancer le container Docker\nXFCE4 + noVNC\nLabel  issat.user=username]:::action

    I[Attribuer un port noVNC\ndisponible entre 7000 et 8000]:::action

    J[Generer la config Nginx\n/etc/nginx/conf.d/username.conf]:::action

    K[Recharger Nginx\nnginx -s reload]:::action

    L{Nginx OK ?}:::decision
    M[Reparer les configs\nfix_nginx_configs.sh]:::error

    N([Session prete\nlabo.issat.local/username/]):::startend

    A --> B
    B -->|"Oui"| C --> D
    B -->|"Non"| D
    D --> E
    E -->|"Non"| F --> G
    E -->|"Oui"| G
    G --> H --> I --> J --> K --> L
    L -->|"Echec"| M --> K
    L -->|"OK"| N
```

---

## 12. Flux de soumission — n8n

```mermaid
sequenceDiagram
    actor Etudiant
    participant BUR as Bureau Virtuel noVNC
    participant CONT as Container Docker
    participant N8N as n8n Workflow
    participant VIG as Vigie
    actor Enseignant

    Note over Etudiant,N8N: Soumission du travail pratique

    Etudiant->>BUR: Depose fichiers dans Rendu/
    Etudiant->>BUR: Clique sur Rendre le TP
    BUR->>CONT: Execution script de soumission
    CONT->>N8N: POST /webhook/rendu-tp\nusername  tp  horodatage

    N8N->>N8N: Validation format et fichiers requis

    alt Fichiers valides
        N8N->>N8N: Archivage dans /rendus/username/tp/
        N8N-->>CONT: 200 OK  Rendu accepte
        CONT-->>BUR: Notification succes
        BUR-->>Etudiant: Travail soumis avec succes
        N8N->>VIG: Signal rendu username tp timestamp
        VIG-->>Enseignant: Notification tableau de bord
    else Fichiers invalides ou manquants
        N8N-->>CONT: 422  Format incorrect
        CONT-->>BUR: Message d erreur detaille
        BUR-->>Etudiant: Verifiez les fichiers requis
    end

    Note over Enseignant,VIG: Consultation des rendus

    Enseignant->>VIG: Consulte la liste des rendus
    VIG-->>Enseignant: Liste etudiants + statut rendu
    Enseignant->>VIG: Telecharge le rendu d un etudiant
    VIG-->>Enseignant: Fichiers du rendu
```
