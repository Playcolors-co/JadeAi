"""Planner schemas."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from pydantic import BaseModel, Field


class StepType(str, Enum):
    CLICK = "click"
    TYPE = "type"
    MOVE = "move"


class PlanStep(BaseModel):
    id: str
    type: StepType
    target: str
    payload: dict[str, str] = Field(default_factory=dict)
    status: str = "pending"


class Plan(BaseModel):
    id: str
    created_at: datetime
    steps: list[PlanStep]
    goal: str
