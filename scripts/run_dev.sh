#!/usr/bin/env bash
set -euo pipefail

export UVICORN_RELOAD_DIRS=services

uvicorn services.gateway.app.main:app --host 0.0.0.0 --port 8080 --reload
