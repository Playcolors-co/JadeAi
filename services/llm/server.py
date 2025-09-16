"""Local LLM stub service."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class LocalLLM:
    temperature: float = 0.3

    def generate(self, prompt: str) -> dict[str, object]:
        steps = [
            {"id": "step-1", "action": "click", "target": "settings"},
            {"id": "step-2", "action": "type", "target": "search", "value": "Display"},
        ]
        return {"prompt": prompt, "steps": steps, "temperature": self.temperature}
