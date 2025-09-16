SHELL := /bin/bash

PROJECT_NAME := jadeai
PYTHON := python3
POETRY := poetry

.PHONY: help install lint format test build up down logs

help:
@echo "Available targets:"
@echo "  install   Install Python dependencies for development"
@echo "  lint      Run static analysis (ruff)"
@echo "  format    Format sources (ruff + black)"
@echo "  test      Run unit tests"
@echo "  build     Build all docker images"
@echo "  up        Start the core docker-compose stack"
@echo "  down      Stop all running containers"
@echo "  logs      Tail gateway logs"

install:
$(PYTHON) -m venv .venv && . .venv/bin/activate && pip install -U pip
. .venv/bin/activate && pip install -r services/gateway/requirements.txt
. .venv/bin/activate && pip install -r services/perception/requirements.txt
. .venv/bin/activate && pip install -r services/llm/requirements.txt
. .venv/bin/activate && pip install -r services/planner/requirements.txt
. .venv/bin/activate && pip install -r services/hid/requirements.txt
. .venv/bin/activate && pip install -r services/memory/requirements.txt
. .venv/bin/activate && pip install -r services/bus/requirements.txt

lint:
. .venv/bin/activate && ruff check services tests

format:
. .venv/bin/activate && ruff format services tests

test:
. .venv/bin/activate && pytest

build:
docker compose build

up:
docker compose up -d

up-%:
docker compose --profile $* up -d

logs:
docker compose logs -f gateway

down:
docker compose down
