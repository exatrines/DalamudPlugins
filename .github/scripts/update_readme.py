#!/usr/bin/env python3
# Replace the README plugins table from pluginmaster.json.

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

TABLE_START = "<!-- PLUGINS_TABLE_START -->"
TABLE_END = "<!-- PLUGINS_TABLE_END -->"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("pluginmaster", nargs="?", default="pluginmaster.json")
    parser.add_argument("readme", nargs="?", default="README.md")
    return parser.parse_args()


def escape_md_cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def cell_text(entry: dict[str, Any], key: str) -> str:
    value = entry.get(key)
    if value is None:
        return ""
    return str(value)


def build_table(entries: list[Any]) -> str:
    lines = [
        TABLE_START,
        "| Icon | Name | Description |",
        "| ---- | ---- | ---- |",
    ]

    for entry in entries:
        if not isinstance(entry, dict):
            continue

        name = cell_text(entry, "Name")
        repo = cell_text(entry, "RepoUrl")
        icon = cell_text(entry, "IconUrl")
        punchline = cell_text(entry, "Punchline")
        description = cell_text(entry, "Description")

        icon_cell = ""
        if icon:
            icon_cell = f'<div align="center"><img src="{icon}" width="50px"></div>'

        name_cell = escape_md_cell(name)
        if repo:
            name_cell = f"[{escape_md_cell(name)}]({repo})"

        desc_cell = escape_md_cell(punchline or description)
        lines.append(f"| {icon_cell} | {name_cell} | {desc_cell} |")

    lines.append(TABLE_END)
    return "\n".join(lines) + "\n"


def replace_table(readme: str, table: str) -> str:
    start = readme.find(TABLE_START)
    end = readme.find(TABLE_END)
    if start < 0 or end < 0:
        raise ValueError("README is missing PLUGINS_TABLE markers")
    if end < start:
        raise ValueError("README PLUGINS_TABLE markers are out of order")

    end += len(TABLE_END)
    if end < len(readme) and readme[end] == "\n":
        end += 1

    return readme[:start] + table + readme[end:]


def main() -> int:
    args = parse_args()
    pluginmaster_path = Path(args.pluginmaster)
    readme_path = Path(args.readme)

    if not pluginmaster_path.is_file():
        print(f"pluginmaster not found: {pluginmaster_path}", file=sys.stderr)
        return 1
    if not readme_path.is_file():
        print(f"README not found: {readme_path}", file=sys.stderr)
        return 1

    try:
        entries = json.loads(pluginmaster_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"Invalid pluginmaster JSON: {exc}", file=sys.stderr)
        return 1

    if not isinstance(entries, list):
        print("pluginmaster JSON must be an array", file=sys.stderr)
        return 1

    original = readme_path.read_text(encoding="utf-8")
    try:
        updated = replace_table(original, build_table(entries))
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    readme_path.write_text(updated, encoding="utf-8", newline="\n")
    print(f"Updated plugins table in {readme_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
