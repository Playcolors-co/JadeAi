"""Planner router."""

from __future__ import annotations

from datetime import datetime
from fastapi import APIRouter
from pydantic import BaseModel

from ..schemas.plan import Plan, PlanStep, StepType

router = APIRouter()


class PlanRequest(BaseModel):
    goal: str


@router.post("/plan", response_model=Plan)
async def create_plan(request: PlanRequest) -> Plan:
    step = PlanStep(id="step-1", type=StepType.CLICK, target="button-1")
    return Plan(id="plan-1", created_at=datetime.utcnow(), steps=[step], goal=request.goal)


@router.get("/plan/{plan_id}", response_model=Plan)
async def get_plan(plan_id: str) -> Plan:
    step = PlanStep(id="step-1", type=StepType.CLICK, target="button-1", status="completed")
    return Plan(id=plan_id, created_at=datetime.utcnow(), steps=[step], goal="demo")
