"""HID passthrough endpoints."""

from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()


class ClickRequest(BaseModel):
    x: int
    y: int
    button: str = "left"


class TextRequest(BaseModel):
    text: str


@router.post("/click")
async def click(payload: ClickRequest) -> dict[str, str | int]:
    return {"status": "ok", "x": payload.x, "y": payload.y, "button": payload.button}


@router.post("/text")
async def type_text(payload: TextRequest) -> dict[str, str]:
    return {"status": "ok", "text": payload.text}
