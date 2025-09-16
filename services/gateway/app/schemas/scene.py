"""Scene graph data models."""

from __future__ import annotations

from pydantic import BaseModel, Field


class BoundingBox(BaseModel):
    x: int = Field(..., ge=0)
    y: int = Field(..., ge=0)
    width: int = Field(..., ge=0)
    height: int = Field(..., ge=0)


class OCRSpan(BaseModel):
    text: str
    confidence: float = Field(..., ge=0, le=1)
    bbox: BoundingBox


class SceneElement(BaseModel):
    id: str
    label: str
    bbox: BoundingBox
    confidence: float = Field(..., ge=0, le=1)
    ocr: list[OCRSpan] = []


class SceneGraph(BaseModel):
    elements: list[SceneElement]
    cursor: BoundingBox | None = None
