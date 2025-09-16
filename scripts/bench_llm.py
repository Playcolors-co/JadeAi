"""LLM latency benchmark stub."""

from __future__ import annotations

import time

from services.llm.server import LocalLLM


def main() -> None:
    llm = LocalLLM()
    start = time.perf_counter()
    llm.generate(prompt="List steps to open settings")
    duration = time.perf_counter() - start
    print(f"LLM generation took {duration * 1000:.2f} ms (stub)")


if __name__ == "__main__":
    main()
