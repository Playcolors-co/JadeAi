"""Simple OCR benchmark stub."""

from __future__ import annotations

import time

from services.perception.service import PerceptionService


def main() -> None:
    service = PerceptionService()
    start = time.perf_counter()
    service.run_ocr("demo frame")
    duration = time.perf_counter() - start
    print(f"OCR inference took {duration * 1000:.2f} ms (stub)")


if __name__ == "__main__":
    main()
