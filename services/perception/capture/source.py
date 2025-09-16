"""Frame capture stub."""

from __future__ import annotations

from typing import Iterable


def capture_frame() -> Iterable[int]:
    """Return a fake frame represented as a list of zeros."""
    return [0] * 10
