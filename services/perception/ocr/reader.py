"""OCR reader stub."""

from __future__ import annotations

from ..schemas import OCRResult


class OCRReader:
    def read(self, frame: str) -> list[OCRResult]:
        return [OCRResult(text="Settings", confidence=0.88, bbox=(100, 200, 120, 32))]
