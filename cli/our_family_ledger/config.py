"""Config management for OurFamilyLedger chat command (TES-44).

Reads/writes the [ai] section of ~/.our-family-ledger/config.toml.
Uses stdlib tomllib (Python 3.11+) for parsing and manual TOML string
construction for writing (no external dependency).
"""

from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_CONFIG_DIR = Path.home() / ".our-family-ledger"
DEFAULT_CONFIG_PATH = DEFAULT_CONFIG_DIR / "config.toml"


@dataclass
class AIConfig:
    """Configuration for the AI chat feature."""

    provider: str = "openai"
    endpoint: str = "https://api.openai.com/v1"
    model: str = "gpt-4o-mini"
    api_key: str = ""


def load_ai_config(path: Path | None = None) -> AIConfig | None:
    """Load AIConfig from config.toml [ai] section.

    Returns None if the config file does not exist or has no [ai] section.
    """
    config_path = path or DEFAULT_CONFIG_PATH
    if not config_path.exists():
        return None

    with open(config_path, "rb") as f:
        try:
            data = tomllib.load(f)
        except tomllib.TOMLDecodeError:
            return None

    ai_section = data.get("ai")
    if not ai_section:
        return None

    return AIConfig(
        provider=ai_section.get("provider", "openai"),
        endpoint=ai_section.get("endpoint", "https://api.openai.com/v1"),
        model=ai_section.get("model", "gpt-4o-mini"),
        api_key=ai_section.get("api_key", ""),
    )


def save_ai_config(config: AIConfig, path: Path | None = None) -> None:
    """Save AIConfig to config.toml [ai] section.

    Preserves any other sections in the existing config file.
    Creates the config directory if it doesn't exist.
    """
    config_path = path or DEFAULT_CONFIG_PATH
    config_path.parent.mkdir(parents=True, exist_ok=True)

    # Load existing TOML content (other sections)
    existing: dict = {}
    if config_path.exists():
        with open(config_path, "rb") as f:
            try:
                existing = tomllib.load(f)
            except tomllib.TOMLDecodeError:
                existing = {}

    # Update [ai] section
    existing["ai"] = {
        "provider": config.provider,
        "endpoint": config.endpoint,
        "model": config.model,
        "api_key": config.api_key,
    }

    # Serialize back to TOML string
    toml_str = _dict_to_toml(existing)

    with open(config_path, "w", encoding="utf-8") as f:
        f.write(toml_str)


def _toml_value(v: object) -> str:
    """Serialize a Python value to its TOML representation."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        # Escape backslashes and double-quotes
        escaped = v.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    raise TypeError(f"Unsupported TOML value type: {type(v)}")


def _dict_to_toml(data: dict) -> str:
    """Convert a flat-sections dict to a TOML string.

    Handles top-level keys and one level of nested table sections.
    Sufficient for config.toml with [ai] and similar sections.
    """
    lines: list[str] = []
    deferred_sections: list[tuple[str, dict]] = []

    for key, value in data.items():
        if isinstance(value, dict):
            deferred_sections.append((key, value))
        else:
            lines.append(f"{key} = {_toml_value(value)}")

    for section_name, section in deferred_sections:
        if lines:
            lines.append("")
        lines.append(f"[{section_name}]")
        for k, v in section.items():
            lines.append(f"{k} = {_toml_value(v)}")

    return "\n".join(lines) + "\n" if lines else ""
