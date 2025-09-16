from __future__ import annotations

import os
from pathlib import Path


def _resolve(value: object) -> object:
    if isinstance(value, str) and value.startswith("${") and value.endswith("}"):
        inner = value[2:-1]
        key, _, default = inner.partition(":")
        return os.getenv(key, default)
    return value


def test_hid_config_defaults() -> None:
    config_path = Path("configs/hid.yml")
    assert config_path.exists()
    data = _parse_simple_yaml(config_path.read_text())

    assert _resolve(data["mode"]) == "bluetooth"
    assert _resolve(data["device_name"]).startswith("JadeAI")
    assert _resolve(data["ble_adapter"]) == "hci0"

    http_cfg = data["http"]
    assert _resolve(http_cfg["bind"]) == "0.0.0.0"
    assert int(_resolve(http_cfg["port"])) == 8003

    hid_section = data["hid"]
    assert int(_resolve(hid_section["appearance"])) == 961
    assert _resolve(hid_section["manufacturer"]) == "JadeAI"
    assert _resolve(hid_section["keyboard"]["enabled"]) in {"true", "True", True}
    assert _resolve(hid_section["mouse"]["enabled"]) in {"true", "True", True}

    safety = data["safety"]
    assert int(_resolve(safety["keypress_delay_ms"])) > 0
    assert int(_resolve(safety["mouse_move_delay_ms"])) > 0
    assert int(_resolve(safety["mouse_step_limit"])) > 0


def _parse_simple_yaml(text: str) -> dict[str, object]:
    root: dict[str, object] = {}
    stack: list[dict[str, object]] = [root]
    indent_levels = [0]

    for raw_line in text.splitlines():
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue

        indent = len(raw_line) - len(raw_line.lstrip(" "))
        while indent_levels and indent < indent_levels[-1]:
            stack.pop()
            indent_levels.pop()

        line = raw_line.strip()
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()

        if not value:
            new_map: dict[str, object] = {}
            stack[-1][key] = new_map
            stack.append(new_map)
            indent_levels.append(indent + 2)
        else:
            stack[-1][key] = value

    return root
