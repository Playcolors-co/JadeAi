"""Planner stub that validates LLM steps against policy."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import List

from services.gateway.app.schemas.plan import Plan, PlanStep, StepType


@dataclass
class Policy:
    blocked: list[str] = field(default_factory=lambda: ["format", "delete"])

    def is_allowed(self, text: str) -> bool:
        return not any(term in text.lower() for term in self.blocked)


@dataclass
class Planner:
    policy: Policy = field(default_factory=Policy)

    def from_llm(self, goal: str, steps: List[dict[str, str]]) -> Plan:
        valid_steps: list[PlanStep] = []
        for idx, step in enumerate(steps, start=1):
            target = step.get("target", "")
            if not self.policy.is_allowed(target):
                continue
            action = StepType(step.get("action", "click"))
            valid_steps.append(
                PlanStep(
                    id=f"step-{idx}",
                    type=action,
                    target=target or "unknown",
                    payload={k: v for k, v in step.items() if k not in {"action", "target"}},
                )
            )
        return Plan(id="plan-generated", created_at=datetime.utcnow(), steps=valid_steps, goal=goal)
