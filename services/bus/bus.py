"""Event bus stub."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from typing import Callable, DefaultDict, List


@dataclass
class EventBus:
    subscribers: DefaultDict[str, List[Callable[[dict[str, object]], None]]] = field(
        default_factory=lambda: defaultdict(list)
    )

    def publish(self, topic: str, message: dict[str, object]) -> None:
        for callback in self.subscribers[topic]:
            callback(message)

    def subscribe(self, topic: str, callback: Callable[[dict[str, object]], None]) -> None:
        self.subscribers[topic].append(callback)
