"""Detector engine stub."""

from __future__ import annotations

from typing import Iterable, List

from ..schemas import Detection


class DetectorEngine:
    """Fake detector that returns a static detection."""

    def infer(self, frame: Iterable[float]) -> List[Detection]:
        return [Detection(label="button", confidence=0.9, bbox=(100, 200, 120, 32))]
