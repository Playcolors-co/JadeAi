"""Event schemas for the JadeAI bus."""

from __future__ import annotations

from datetime import datetime
from pydantic import BaseModel


class Event(BaseModel):
    id: str
    topic: str
    created_at: datetime
    payload: dict[str, object]
