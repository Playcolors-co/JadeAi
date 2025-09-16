"""In-memory store stub."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List


@dataclass
class MemoryStore:
    records: List[dict[str, object]] = field(default_factory=list)

    def add(self, record: dict[str, object]) -> None:
        self.records.append(record)

    def query(self, limit: int = 10) -> List[dict[str, object]]:
        return self.records[-limit:]
