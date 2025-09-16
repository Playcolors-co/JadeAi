"""HID control stub."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List


@dataclass
class HIDEvent:
    type: str
    payload: dict[str, object]


@dataclass
class HIDController:
    queue: List[HIDEvent] = field(default_factory=list)

    def click(self, x: int, y: int, button: str = "left") -> None:
        self.queue.append(HIDEvent(type="click", payload={"x": x, "y": y, "button": button}))

    def type_text(self, text: str) -> None:
        self.queue.append(HIDEvent(type="text", payload={"text": text}))

    def dequeue(self) -> HIDEvent | None:
        return self.queue.pop(0) if self.queue else None
