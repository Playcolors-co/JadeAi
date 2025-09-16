"""Utility to convert ONNX models into TensorRT engines (stub)."""

from __future__ import annotations

import argparse
from pathlib import Path


def build_engine(model_path: Path, output: Path) -> None:
    """Pretend to build a TensorRT engine by copying the file."""
    output.write_bytes(model_path.read_bytes())
    print(f"[stub] Copied {model_path} -> {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert ONNX to TRT engine")
    parser.add_argument("model", type=Path, help="Path to the ONNX model")
    parser.add_argument("--output", type=Path, default=Path("model.engine"), help="Output engine path")
    args = parser.parse_args()

    if not args.model.exists():
        raise SystemExit(f"Model not found: {args.model}")

    build_engine(args.model, args.output)


if __name__ == "__main__":
    main()
