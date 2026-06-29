#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SELECTED_FILE = REPO_ROOT / "themes" / "selected.nix"


def read_themes() -> dict[str, dict[str, object]]:
    output = subprocess.check_output(
        [
            "nix",
            "eval",
            "--impure",
            "--json",
            "--expr",
            "let themes = import ./themes/themes.nix; in builtins.mapAttrs (_: theme: theme // { wallpaper = toString theme.wallpaper; }) themes",
        ],
        cwd=REPO_ROOT,
        text=True,
    )
    return json.loads(output)


def theme_names() -> list[str]:
    return sorted(read_themes())


def selected_theme() -> str:
    return SELECTED_FILE.read_text().strip().strip('"')


def select_theme(name: str) -> None:
    names = theme_names()
    if name not in names:
        raise SystemExit(f"Unknown theme '{name}'. Available: {', '.join(names)}")
    SELECTED_FILE.write_text(f'"{name}"\n')
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
        print(f"{marker} {name} | {Path(theme['wallpaper']).relative_to(REPO_ROOT)}")


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
