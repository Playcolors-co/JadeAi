import atexit
import json
import os
import socket
import subprocess
import threading
import time

from flask import Flask, jsonify, request

import bt_manager

APP_ROOT = os.path.dirname(os.path.abspath(__file__))
DAEMON_PATH = os.path.join(APP_ROOT, "bthid")
SOCKET_PATH = "/tmp/jadeai-bthid.sock"

app = Flask(__name__)

_daemon_lock = threading.Lock()
_daemon_process = None


def _escape_text(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )


def _ensure_daemon() -> None:
    global _daemon_process
    with _daemon_lock:
        if _daemon_process is None or _daemon_process.poll() is not None:
            _daemon_process = subprocess.Popen([DAEMON_PATH, "--daemon"])
            time.sleep(1.0)


def _shutdown_daemon() -> None:
    global _daemon_process
    if _daemon_process is None:
        return
    try:
        _send_command("SHUTDOWN")
    except Exception:
        pass
    if _daemon_process is not None:
        try:
            _daemon_process.wait(timeout=2.0)
        except Exception:
            _daemon_process.terminate()
    _daemon_process = None


def _send_command(command: str) -> str:
    _ensure_daemon()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.connect(SOCKET_PATH)
        client.sendall((command + "\n").encode("utf-8"))
        data = b""
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            data += chunk
            if b"\n" in chunk:
                break
    response = data.decode("utf-8").strip()
    if response.startswith("ERR"):
        raise RuntimeError(response[3:].strip())
    if response.startswith("OK"):
        payload = response[2:].strip()
        return payload
    return response


def _parse_status(payload: str) -> dict:
    if not payload:
        return {}
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return {"raw": payload}


@atexit.register
def _cleanup_on_exit() -> None:
    _shutdown_daemon()


@app.route("/hid/text", methods=["POST"])
def type_text():
    body = request.get_json(force=True)
    text = body.get("text", "")
    _send_command("TYPE " + _escape_text(text))
    return "", 204


@app.route("/hid/move", methods=["POST"])
def move_mouse():
    body = request.get_json(force=True)
    dx = int(body.get("x", 0))
    dy = int(body.get("y", 0))
    wheel = body.get("wheel")
    command = f"MOVE {dx} {dy}"
    if wheel is not None:
        command += f" {int(wheel)}"
    _send_command(command)
    return "", 204


@app.route("/hid/click", methods=["POST"])
def click():
    body = request.get_json(force=True)
    button = body.get("button", "left")
    _send_command(f"CLICK {button}")
    return "", 204


@app.route("/hid/status", methods=["GET"])
def status():
    hid_status = {}
    try:
        payload = _send_command("STATUS")
        hid_status = _parse_status(payload)
    except Exception as exc:  # pragma: no cover - diagnostics
        hid_status = {"error": str(exc)}
    adapter_status = bt_manager.get_status()
    hid_status.update(adapter_status)
    return jsonify(hid_status)


@app.route("/hid/disconnect", methods=["POST"])
def disconnect():
    _send_command("DISCONNECT")
    return "", 204


@app.route("/hid/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    _ensure_daemon()
    app.run(host="0.0.0.0", port=5001)
else:
    _ensure_daemon()
