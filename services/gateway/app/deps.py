"""Dependency helpers for the FastAPI gateway."""

from __future__ import annotations

from functools import lru_cache
from pydantic import BaseSettings


class Settings(BaseSettings):
    environment: str = "development"
    bus_url: str = "nats://bus:4222"
    planner_url: str = "http://planner:8002"
    perception_url: str = "http://perception:8001"
    hid_url: str = "http://hid:8003"
    memory_url: str = "http://memory:8004"

    class Config:
        env_prefix = "JADEAI_"


@lru_cache()
def get_settings() -> Settings:
    """Return cached application settings."""
    return Settings()
