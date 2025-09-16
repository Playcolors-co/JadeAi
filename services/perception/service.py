"""Stub perception service orchestrating capture, detection, and OCR."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List

from .annotate import overlay
from .capture import source
from .detector.engine import DetectorEngine
from .ocr.reader import OCRReader
from .schemas import Detection, OCRResult


@dataclass
class PerceptionService:
    detector: DetectorEngine | None = None
    ocr_reader: OCRReader | None = None

    def __post_init__(self) -> None:
        if self.detector is None:
            self.detector = DetectorEngine()
        if self.ocr_reader is None:
            self.ocr_reader = OCRReader()

    def capture(self) -> Iterable[int]:
        return source.capture_frame()

    def run_inference(self, frame: Iterable[int]) -> List[Detection]:
        assert self.detector is not None
        return self.detector.infer(frame)

    def run_ocr(self, frame: str) -> List[OCRResult]:
        assert self.ocr_reader is not None
        return self.ocr_reader.read(frame)

    def annotate(self, detections: List[Detection]) -> str:
        return overlay.draw(detections)
