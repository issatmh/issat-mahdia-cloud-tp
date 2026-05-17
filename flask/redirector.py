"""
Redirecteur Flask — redirector.py
Port   : 8080
Systemd: redirector.service
Rôle   : Reçoit les requêtes Nginx, vérifie la session Authentik,
         lance le bon container Docker et redirige vers noVNC.
"""

from flask import Flask, redirect, jsonify, request
import docker
import requests as req
import subprocess
import time
import os

app = Flask(__name__)
docker_cli = docker.from_env()

AUTHENTIK_URL         = "http://127.0.0.1:9000"
LANCER_SCRIPT         = "/home/docker/authentik/lancer_kasm.sh"
LANCER_WINDOWS_SCRIPT = "/home/docker/authentik/lancer_windows.sh"
WINDOWS_TPS           = {"windows"}
ANNEE_UNIV            = "25-26"


def get_user_from_session(session_cookie):
    """Interroge l'API Authentik pour récupérer les infos de l'étudiant connecté."""
    try:
        response = req.get(
            f"{AUTHENTIK_URL}/api/v3/core/users/me/",
            cookies={"authentik_session": session_cookie},
            timeout=5
        )
        if response.status_code == 200:
            data  = response.json()
            user  = data.get("user") or data
            attrs = user.get("attributes") or {}
            return {
                "username":    user.get("username", ""),
                "groups":      ",".join([g.get("name", "") for g in user.get("groups_obj", [])]),
                "annee_univ":  attrs.get("annee_univ", ANNEE_UNIV),
                "niveau":      attrs.get("niveau", ""),
                "sous_groupe": attrs.get("sous_groupe", ""),
            }
    except Exception as e:
        print(f"Erreur API Authentik: {e}")
    return None


def get_active_container(username, tp_name=None):
    """Recherche un container Docker actif pour cet étudiant."""
    try:
        containers = docker_cli.containers.list(
            filters={"name": username, "status": "running"}
        )
        for c in containers:
            parts = c.name.split("-")
            if username in parts:
                if tp_name is None or c.name.startswith(tp_name + "-"):
                    return c
    except Exception as e:
        print(f"Erreur Docker: {e}")
    return None


def container_url(container_name):
    """Retourne l'URL noVNC selon le type de container (Linux ou Windows)."""
    if container_name.startswith("windows-"):
        return f"/kasm/{container_name}/"
    return (
        f"/kasm/{container_name}/vnc_auto.html"
        f"?autoconnect=true&reconnect=true&reconnect_delay=1000"
        f"&resize=scale&quality=6&path=kasm/{container_name}/websockify"
    )


@app.route("/auth-kasm")
def auth_kasm():
    """Vérifie que l'étudiant connecté accède à son propre container (anti-usurpation).
    Utilisé comme sous-requête interne Nginx (auth_request)."""
    session_cookie = request.cookies.get("authentik_session")
    if not session_cookie:
        return "", 401

    info = get_user_from_session(session_cookie)
    if not info:
        return "", 401

    username = info["username"]
    original_uri = request.headers.get("X-Original-URI", "")
    parts = original_uri.strip("/").split("/")

    if len(parts) >= 2 and parts[0] == "kasm":
        container_name = parts[1]
        name_parts = container_name.split("-")
        if username not in name_parts:
            print(f"[BLOCKED] {username} → {container_name}")
            return "", 403

    return "", 200


@app.route("/lancer-tp/<tp_name>")
def lancer_tp(tp_name):
    """Lance le container du TP demandé pour l'étudiant connecté."""
    session_cookie = request.cookies.get("authentik_session")
    if not session_cookie:
        return redirect("http://labo.issat.local")

    info = get_user_from_session(session_cookie)
    if not info:
        return redirect("http://labo.issat.local")

    username    = info["username"]
    groups      = info["groups"]
    annee_univ  = info["annee_univ"]
    niveau      = info["niveau"]
    sous_groupe = info["sous_groupe"]

    container_name = f"{tp_name}-{username}-{annee_univ}"
    active = get_active_container(username, tp_name)

    if active:
        print(f"[ALREADY RUNNING] {username} → {active.name}")
        return redirect(container_url(active.name))

    print(f"[LAUNCH] {username} → {container_name} (niveau={niveau}, sg={sous_groupe})")

    script = LANCER_WINDOWS_SCRIPT if tp_name in WINDOWS_TPS else LANCER_SCRIPT
    result = subprocess.run(
        ["sudo", "-n", "bash", script,
         username, groups, tp_name, annee_univ, niveau, sous_groupe],
        capture_output=True, text=True, timeout=60
    )

    if result.returncode != 0:
        return f"<h2>Erreur lancement TP {tp_name}</h2><pre>{result.stderr}</pre>", 500

    time.sleep(4)
    return redirect(container_url(container_name))


@app.route("/bureau")
def redirect_to_kasm():
    """Redirige l'étudiant vers son container actif."""
    session_cookie = request.cookies.get("authentik_session")
    if not session_cookie:
        return redirect("http://labo.issat.local")

    info = get_user_from_session(session_cookie)
    if not info:
        return redirect("http://labo.issat.local")

    username = info["username"]
    active = get_active_container(username)

    if not active:
        return jsonify({
            "erreur": f"Aucun TP actif pour {username}",
            "solution": "Retournez sur le portail et choisissez un TP."
        }), 404

    return redirect(container_url(active.name))


@app.route("/status")
def status():
    """Retourne la liste de tous les containers actifs (JSON)."""
    result = []
    for c in docker_cli.containers.list():
        labels   = c.labels or {}
        bindings = c.ports.get("6901/tcp") or c.ports.get("8006/tcp")
        port     = bindings[0]["HostPort"] if bindings else "inconnu"
        result.append({
            "container":  c.name,
            "etudiant":   labels.get("etudiant", ""),
            "tp":         labels.get("tp", ""),
            "groupe":     labels.get("groupe", ""),
            "annee_univ": labels.get("annee_univ", ""),
            "port":       port,
            "url":        f"http://labo.issat.local/kasm/{c.name}/",
            "statut":     c.status
        })
    return jsonify({"redirecteur": "actif", "total": len(result), "containers": result})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
