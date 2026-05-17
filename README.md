# Mini-Cloud Pédagogique Intelligent — ISSAT Mahdia

<div align="center">

**Conception d'un Mini-Cloud Pédagogique Intelligent basé sur Proxmox, Docker et l'Automatisation IA pour la Centralisation des Travaux Pratiques à l'ISSAT Mahdia**

![Proxmox](https://img.shields.io/badge/Proxmox-VE-E57000?style=for-the-badge&logo=proxmox&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-009639?style=for-the-badge&logo=nginx&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-000000?style=for-the-badge&logo=flask&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![n8n](https://img.shields.io/badge/n8n-EA4B71?style=for-the-badge&logo=n8n&logoColor=white)

*Mémoire de Fin d'Études — Licence TIC · ISSAT Mahdia · Université de Monastir · 2025/2026*

**[Voir tous les diagrammes →](docs/diagrams.md)**

</div>

---

## Overview

Traditional IT labs at **ISSAT Mahdia** face critical limitations: heterogeneous workstations, costly maintenance, environment inconsistencies between sessions, and no remote access for students outside scheduled lab hours.

This project delivers a **centralized, browser-accessible Mini-Cloud platform** that provides every student with an isolated, reproducible virtual desktop — launched on demand, destroyed on logout — with zero client-side software installation required.

Each practical lab session (TP) maps to a **dedicated Docker image** pre-configured with the exact toolset required, eliminating the "it works on my machine" problem at scale.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      ISSAT Network                          │
│   Student/Teacher Workstations  ──►  pfSense (Firewall)     │
└──────────────────────────────────────┬──────────────────────┘
                                       │ NAT / Routing
┌──────────────────────────────────────▼──────────────────────┐
│                   Private Lab Network                       │
│                                                             │
│  ┌─────────────────── Proxmox VE ──────────────────────┐   │
│  │                                                      │   │
│  │   ┌─── Ubuntu Server ────────────────────────────┐  │   │
│  │   │                                              │  │   │
│  │   │  Nginx (Reverse Proxy)                       │  │   │
│  │   │    │                                         │  │   │
│  │   │    ├── Authentik (SSO / OIDC)                │  │   │
│  │   │    ├── Vigie     (Monitoring Dashboard)      │  │   │
│  │   │    ├── n8n       (TP Submission Automation)  │  │   │
│  │   │    └── Docker Containers (per student/TP)    │  │   │
│  │   │         ├── Linux XFCE4 (via noVNC)          │  │   │
│  │   │         └── Windows 10  (via QEMU/KVM+noVNC) │  │   │
│  │   │                                              │  │   │
│  │   │  Flask Services                              │  │   │
│  │   │    ├── webhook_receiver.py                   │  │   │
│  │   │    └── redirector.py                         │  │   │
│  │   └──────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### DNS Resolution (local)

| Domain | Service |
|---|---|
| `issat.local` | Authentik SSO portal |
| `labo.issat.local` | TP platform (Nginx entry point) |
| `dash.issat.local` | Vigie monitoring dashboard |
| `n8n.issat.local` | n8n automation / TP submission |

---

## Tech Stack

| Layer | Technology | Role |
|---|---|---|
| Hypervisor | **Proxmox VE** | Host VMs and containers |
| Firewall | **pfSense** | Network isolation, NAT, DHCP, DNS |
| Containerization | **Docker / Docker Compose** | Isolated per-TP environments |
| Authentication | **Authentik** | SSO (OAuth2/OIDC), identity & session management |
| Reverse Proxy | **Nginx** | Single entry point, dynamic config generation |
| Virtual Desktop (Linux) | **XFCE4 + noVNC** | Browser-based Linux desktop |
| Virtual Desktop (Windows) | **QEMU/KVM + noVNC** | Browser-based Windows 10 desktop |
| Automation | **n8n** | TP work submission workflow |
| Monitoring | **Vigie** (custom) | Real-time container dashboard + alerts |
| Backend | **Flask (Python)** | Webhook receiver, identity redirector |
| Scripting | **Bash** | Container lifecycle management |

---

## Key Features

### For Students
- **Single Sign-On** — one account, access to all authorized TPs via Authentik
- **Browser-only access** — no VPN, no client software, works on any device
- **Linux or Windows virtual desktop** — launched in seconds on TP selection
- **Data persistence** — personal files preserved across sessions via Docker volumes
- **Session isolation** — one active TP at a time per student; resources freed on logout

### For Teachers
- **Vue Examen** — real-time surveillance of all student desktops during exams
- **Presence management** — automated attendance tracking with CSV export
- **Group management** — assign students to groups and control TP access per group
- **TP lifecycle control** — start, manage, and terminate student sessions

### For Administrators
- **Vigie Dashboard** — live monitoring of all active containers (CPU, RAM, status)
- **Configurable alerts** — threshold-based notifications on critical resource usage
- **Automated Nginx config** — dynamic reverse proxy entries generated per session
- **Admin commands** — full container, Nginx, and volume management via CLI

---

## Repository Structure

```
issatmh/
├── authentik/
│   └── docker-compose.yml          # Authentik SSO deployment
├── nginx/
│   ├── nginx.conf                  # Main reverse proxy config
│   ├── conf.d/
│   │   ├── labo.issat.local.conf   # TP platform vhost
│   │   ├── vigie.conf              # Monitoring dashboard vhost
│   │   └── n8n.conf                # n8n workflow vhost
│   └── templates/
│       └── student.conf.j2         # Dynamically generated per-session config
├── docker/
│   ├── base/
│   │   └── Dockerfile              # Base image (Linux XFCE4 + noVNC)
│   └── tp-*/
│       └── Dockerfile              # Per-TP specialized images
├── scripts/
│   ├── lancer_issat.sh             # Launch Linux container for a student/TP
│   ├── lancer_windows.sh           # Launch Windows container
│   ├── stopper_kasm.sh             # Stop and clean up a student container
│   └── fix_nginx_configs.sh        # Repair broken Nginx configurations
├── vigie/
│   └── app/                        # Monitoring dashboard (Flask)
├── flask/
│   ├── webhook_receiver.py         # Authentik webhook handler
│   └── redirector.py               # Identity-based session redirector
├── n8n/
│   └── workflows/                  # TP submission automation workflows
├── docs/
│   └── architecture/               # Architecture diagrams
└── README.md
```

---

## Prerequisites

**Hardware (minimum)**

| Component | Specification |
|---|---|
| CPU | x86-64, virtualization support (VT-x/AMD-V) |
| RAM | 32 GB recommended |
| Storage | 500 GB SSD |
| Network | 1 Gbps |

**Software**

- Proxmox VE 8.x
- Ubuntu Server 22.04 LTS (deployed as Proxmox VM)
- Docker Engine 24+
- Docker Compose v2
- pfSense 2.7+

---

## Deployment

> **Note:** This platform is designed for deployment on an institutional on-premises server. All IP addresses and domain names below are placeholders — adapt them to your environment.

### 1. Network Setup

Configure pfSense with two interfaces:
- **WAN** — connected to the institutional network (`<ISSAT_NETWORK>`)
- **LAN** — private lab network (`<LAB_NETWORK>`)

Add DNS overrides in pfSense (Services → DNS Resolver → Host Overrides):

```
issat.local      → <SERVER_IP>
labo.issat.local → <SERVER_IP>
dash.issat.local → <SERVER_IP>
n8n.issat.local  → <SERVER_IP>
```

### 2. Deploy Authentik (SSO)

```bash
cd authentik/
# Edit .env with your secret keys (never commit .env to git)
cp .env.example .env
docker compose up -d
```

Access the admin interface at `http://issat.local/if/admin/` to configure applications and groups.

### 3. Deploy Nginx

```bash
# Copy configuration files
cp nginx/nginx.conf /etc/nginx/nginx.conf
cp nginx/conf.d/* /etc/nginx/conf.d/

nginx -t && systemctl reload nginx
```

### 4. Build Docker Images

```bash
# Build the base Linux desktop image
docker build -t issat/base:latest docker/base/

# Build per-TP images (example: TP réseau)
docker build -t issat/tp-reseau:latest docker/tp-reseau/
```

Image naming convention: `issat/<tp-slug>:<version>`

### 5. Launch a Student Session

```bash
# Linux desktop
bash scripts/lancer_issat.sh <username> <tp-slug>

# Windows desktop
bash scripts/lancer_windows.sh <username> <tp-slug>
```

### 6. Start Flask Services

```bash
cd flask/
pip install -r requirements.txt
python webhook_receiver.py &
python redirector.py &
```

### 7. Deploy Vigie and n8n

```bash
# Vigie monitoring dashboard
cd vigie/ && docker compose up -d

# n8n automation
cd n8n/ && docker compose up -d
```

---

## Usage

### Student Workflow

1. Open a browser and navigate to `http://labo.issat.local`
2. Log in with institutional credentials (SSO via Authentik)
3. Select an available TP from the catalog
4. A dedicated Docker container launches automatically
5. The virtual desktop opens directly in the browser (noVNC)
6. Submit work via the integrated n8n form before logout
7. Logout — the container is stopped, resources are released

### Teacher Workflow

1. Log in to Vigie at `http://dash.issat.local`
2. Create a TP session and assign student groups
3. Monitor attendance in real time
4. Use **Vue Examen** mode to view student desktops live
5. Export attendance report as CSV

---

## Administration

### Container Management

```bash
# List active student containers
docker ps --filter "label=issat.role=student"

# Stop a specific student's container
bash scripts/stopper_kasm.sh <username>

# Repair all Nginx configurations
bash scripts/fix_nginx_configs.sh
```

### Adding a New TP

1. Create a new Dockerfile in `docker/tp-<name>/`
2. Build and tag the image: `docker build -t issat/tp-<name>:latest .`
3. Declare the TP as an Authentik application (Provider: OAuth2/OIDC)
4. Assign the TP to the appropriate student group in Authentik
5. The TP automatically appears in the student catalog

---

## Security

- **Network isolation**: pfSense enforces strict LAN rules; the lab subnet is not directly reachable from the ISSAT WAN
- **Double access control**: Nginx (`redirector.py`) verifies identity via the Authentik API before serving any virtual desktop
- **Session isolation**: a student can only access their own container; cross-container access is blocked at the Nginx layer
- **Single active session**: the platform enforces one active TP per student at a time

---

## Authors

| Name | Role |
|---|---|
| **Malek Rebei** | Co-author — Infrastructure, Docker, Scripting |
| **Said Yampa Moubarak** | Co-author — Backend, Authentik, Vigie, Automation |

**Supervisor:** Mr. Abdelrahim Chiha — ISSAT Mahdia

**Jury:**
- Mme Souad Zid — Présidente
- Mr Mohamed Zaibi — Examinateur

---

## Institution

**Institut Supérieur des Sciences Appliquées et de Technologie de Mahdia (ISSAT-MH)**
Université de Monastir — République Tunisienne

---

## License

This project was developed as a final-year academic project (Mémoire de Fin d'Études) at ISSAT Mahdia.
All rights reserved — © 2026 Malek Rebei & Said Yampa Moubarak.
