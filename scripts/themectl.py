#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
THEMES_FILE = REPO_ROOT / "themes" / "default.nix"
SELECTED_FILE = REPO_ROOT / "themes" / "selected.nix"
LOCAL_SELECTED_FILE = REPO_ROOT / "themes" / "local-selected.nix"
JSON_START = "builtins.fromJSON ''"
JSON_END = "'';"


def read_themes() -> dict[str, dict[str, object]]:
    text = THEMES_FILE.read_text()
    start = text.index(JSON_START) + len(JSON_START)
    end = text.index(JSON_END, start)
    return json.loads(text[start:end].strip())


def theme_names() -> list[str]:
    return sorted(read_themes())


def selected_theme() -> str:
    selected_file = LOCAL_SELECTED_FILE if LOCAL_SELECTED_FILE.exists() else SELECTED_FILE
    return selected_file.read_text().strip().strip('"')


def select_theme(name: str) -> None:
    names = theme_names()
    if name not in names:
        raise SystemExit(f"Unknown theme '{name}'. Available: {', '.join(names)}")
    LOCAL_SELECTED_FILE.write_text(f'"{name}"\n')
    print(f"Selected theme: {name}")


def print_themes() -> None:
    current = selected_theme()
    for name in theme_names():
        marker = "*" if name == current else " "
        print(f"{marker} {name}")


def print_wallpapers() -> None:
    current = selected_theme()
    for name, theme in sorted(read_themes().items()):
        marker = "*" if name == current else " "
        print(f"{marker} {name} | ../assets/wallpapers/{theme['wallpaper']}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Small declarative theme helper.")
    parser.add_argument("command", choices=["theme", "wallpaper"])
    parser.add_argument("name", nargs="?", default="")
    args = parser.parse_args()

    if args.command == "theme":
        if args.name:
            select_theme(args.name)
        else:
            print_themes()
    elif args.command == "wallpaper":
        if args.name:
            select_theme(args.name)
        else:
            print_wallpapers()


if __name__ == "__main__":
    main()
