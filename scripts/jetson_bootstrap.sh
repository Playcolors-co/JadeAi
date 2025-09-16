#!/usr/bin/env bash
set -euo pipefail

if ! command -v nvpmodel >/dev/null; then
  echo "[WARN] Jetson utilities not found. Ensure JetPack is installed." >&2
fi

echo "Updating apt repositories..."
sudo apt-get update -y
sudo apt-get install -y python3-pip python3-dev python3-venv libssl-dev libffi-dev

echo "Installing Python requirements..."
pip3 install --upgrade pip wheel
pip3 install -r services/perception/requirements.txt
pip3 install -r services/llm/requirements.txt

echo "Bootstrap complete."
