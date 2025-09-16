"""Annotation helpers."""

from __future__ import annotations

from ..schemas import Detection


def draw(detections: list[Detection]) -> str:
    return f"Rendered {len(detections)} detections"
