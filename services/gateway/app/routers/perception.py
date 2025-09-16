"""Perception router."""

from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

from ..schemas.scene import BoundingBox, SceneElement, SceneGraph

router = APIRouter()


class FramePayload(BaseModel):
    frame_id: str
    description: str | None = None


@router.post("/analyse", response_model=SceneGraph)
async def analyse_frame(payload: FramePayload) -> SceneGraph:
    element = SceneElement(
        id="button-1",
        label="settings",
        bbox=BoundingBox(x=100, y=200, width=120, height=32),
        confidence=0.95,
        ocr=[],
    )
    return SceneGraph(elements=[element])
