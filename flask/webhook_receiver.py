"""
Récepteur de webhooks — webhook_receiver.py
Port   : 9001
Systemd: webhook-labo.service
Rôle   : Reçoit les événements login/logout d'Authentik et déclenche
         automatiquement le lancement/arrêt des containers étudiants.

Actions traitées :
  login / login_success / launch_tp → lancer_kasm.sh ou lancer_windows.sh
  logout                             → stopper_kasm.sh
  autres                             → ignorées (200 ignored)
"""

from flask import Flask, request, jsonify
import subprocess
import logging
import os
import json

WEBHOOK_PORT          = 9001
SCRIPTS_DIR           = "/home/docker/authentik"
LANCER_SCRIPT         = os.path.join(SCRIPTS_DIR, "lancer_kasm.sh")
LANCER_WINDOWS_SCRIPT = os.path.join(SCRIPTS_DIR, "lancer_windows.sh")
STOPPER_SCRIPT        = os.path.join(SCRIPTS_DIR, "stopper_kasm.sh")
WINDOWS_TPS           = {"windows"}

LAUNCH_ACTIONS = {"launch_tp", "custom_notification_test", "login", "login_success"}
DEFAULT_TP     = "desktop"

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

app = Flask(__name__)


def run_script(script, *args):
    try:
        cmd    = ["sudo", "-n", "bash", script] + [str(a) for a in args]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        if result.returncode == 0:
            log.info(f"Script OK: {output.strip()}")
            return True, output
        log.error(f"Script ECHEC (code={result.returncode}): {output}")
        return False, output
    except subprocess.TimeoutExpired:
        log.error("Script timeout (>60s)")
        return False, "timeout"
    except Exception as e:
        log.exception(f"Erreur script: {e}")
        return False, str(e)


def extract_payload(data):
    user  = data.get("user") or {}
    attrs = user.get("attributes") or {}
    return {
        "action":      str(data.get("action") or "").strip(),
        "tp":          str(data.get("tp") or DEFAULT_TP).strip(),
        "username":    str(user.get("username") or "").strip(),
        "groups": (",".join(str(g) for g in user.get("groups") or [])
                   if isinstance(user.get("groups"), list)
                   else str(user.get("groups") or "")).strip(),
        "annee_univ":  str(attrs.get("annee_univ")  or "25-26").strip(),
        "niveau":      str(attrs.get("niveau")      or "").strip(),
        "sous_groupe": str(attrs.get("sous_groupe") or "").strip(),
    }


@app.route("/webhook", methods=["POST"])
def webhook():
    raw_body = request.get_data(as_text=True)
    try:
        data = json.loads(raw_body) if raw_body else {}
    except Exception as e:
        log.error(f"JSON invalide: {e} | body={raw_body[:200]}")
        return jsonify({"error": "JSON invalide"}), 400

    if not data:
        return jsonify({"error": "payload vide"}), 400

    p = extract_payload(data)
    if not p["username"]:
        return jsonify({"error": "username manquant"}), 400

    log.info(f"Webhook action='{p['action']}' user='{p['username']}' tp='{p['tp']}'")

    if p["action"] in LAUNCH_ACTIONS:
        script = LANCER_WINDOWS_SCRIPT if p["tp"] in WINDOWS_TPS else LANCER_SCRIPT
        success, _ = run_script(
            script,
            p["username"], p["groups"], p["tp"],
            p["annee_univ"], p["niveau"], p["sous_groupe"],
        )
        return jsonify({
            "status":    "started" if success else "error",
            "user":      p["username"],
            "tp":        p["tp"],
            "container": f"{p['tp']}-{p['username']}-{p['annee_univ']}",
        }), (200 if success else 500)

    if p["action"] == "logout":
        success, _ = run_script(STOPPER_SCRIPT, p["username"])
        return jsonify({
            "status": "stopped" if success else "error",
            "user":   p["username"]
        }), (200 if success else 500)

    return jsonify({"status": "ignored", "action": p["action"]}), 200


@app.route("/health")
def health():
    return jsonify({"status": "ok"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=WEBHOOK_PORT, debug=False)
