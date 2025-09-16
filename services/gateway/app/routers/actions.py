"""Action execution router."""

from __future__ import annotations

from fastapi import APIRouter

from ..schemas.plan import PlanStep

router = APIRouter()


@router.post("/execute")
async def execute_action(step: PlanStep) -> dict[str, str]:
    # In a real implementation this would forward to the HID service
    return {"status": "queued", "step_id": step.id}
