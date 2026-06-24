#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
IDENT = r"[A-Za-z_][A-Za-z0-9_+.-]*"
IGNORED_PKGS_ATTRS = {
    "callPackage",
    "mkShell",
    "runCommand",
    "stdenv",
    "writeShellApplication",
}


def tracked_or_nix_files() -> list[Path]:
    try:
        output = subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
            cwd=REPO_ROOT,
            text=True,
        )
        files = [REPO_ROOT / line for line in output.splitlines()]
    except (OSError, subprocess.CalledProcessError):
        files = sorted(REPO_ROOT.rglob("*.nix"))

    return sorted(
        path
        for path in files
        if path.exists()
        and path.suffix == ".nix"
        and ".git" not in path.parts
        and path.name != "hardware-configuration.nix"
    )


def split_comment(line: str) -> tuple[str, str]:
    in_string = False
    escaped = False
    for index, char in enumerate(line):
        if char == '"' and not escaped:
            in_string = not in_string
        if char == "#" and not in_string:
            return line[:index], line[index + 1 :].strip()
        escaped = char == "\\" and not escaped
    return line, ""


def list_context(line: str) -> str | None:
    match = re.search(r"with\s+(pkgs(?:\.[A-Za-z0-9_+.-]+)*)\s*;\s*\[", line)
    if match:
        return match.group(1)
    return None


def starts_list_without_with(line: str) -> bool:
    return bool(re.search(r"=\s*\[", line))


def bracket_delta(line: str) -> int:
    return line.count("[") - line.count("]")


def tokens_from_list_line(code: str) -> list[str]:
    stripped = code.strip()
    if "[" in stripped:
        stripped = stripped.split("[", 1)[1]
    stripped = re.sub(r"^\[", "", stripped)
    stripped = re.sub(r"\]($|;).*", "", stripped)
    tokens = []
    for token in re.findall(rf"(?:pkgs(?:\.{IDENT})+|{IDENT})", stripped):
        if token in {"with", "let", "in", "if", "then", "else", "true", "false", "null"}:
            continue
        tokens.append(token)
    return tokens


def normalize_token(token: str, context: str | None) -> str | None:
    if token.startswith("pkgs."):
        first_attr = token.split(".", 2)[1]
        if first_attr in IGNORED_PKGS_ATTRS:
            return None
        return token
    if context:
        return f"{context}.{token}"
    return None


def extract_inline_pkgs(code: str) -> list[str]:
    refs = []
    for match in re.finditer(rf"\bpkgs\.({IDENT}(?:\.{IDENT})*)", code):
        if code[max(0, match.start() - 5) : match.start()] == "with ":
            continue
        full = f"pkgs.{match.group(1)}"
        first_attr = match.group(1).split(".", 1)[0]
        if first_attr not in IGNORED_PKGS_ATTRS:
            refs.append(full)
    for match in re.finditer(
        r"inputs\.hyprland\.packages\.\$\{pkgs\.stdenv\.hostPlatform\.system\}\.([A-Za-z0-9_.-]+)",
        code,
    ):
        refs.append(f"inputs.hyprland.packages.${{system}}.{match.group(1)}")
    return refs


def scan_file(path: Path) -> list[dict[str, object]]:
    rows = []
    contexts: list[tuple[str | None, int]] = []

    for lineno, raw_line in enumerate(path.read_text().splitlines(), start=1):
        code, note = split_comment(raw_line)
        stripped = code.strip()

        context = list_context(code)
        if context is not None:
            contexts.append((context, bracket_delta(code)))
        elif contexts:
            current_context, depth = contexts[-1]
            contexts[-1] = (current_context, depth + bracket_delta(code))
        elif starts_list_without_with(code):
            contexts.append((None, bracket_delta(code)))

        active_context = contexts[-1][0] if contexts else None
        refs = []

        if contexts:
            for token in tokens_from_list_line(code):
                ref = normalize_token(token, active_context)
                if ref:
                    refs.append(ref)
        refs.extend(extract_inline_pkgs(code))

        seen = set()
        for ref in refs:
            if ref in seen:
                continue
            seen.add(ref)
            rows.append(
                {
                    "package": ref,
                    "file": str(path.relative_to(REPO_ROOT)),
                    "line": lineno,
                    "note": note,
                }
            )

        while contexts and contexts[-1][1] <= 0:
            contexts.pop()

    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="List package references from repo Nix files.")
    parser.add_argument("--json", action="store_true", help="print JSON instead of a table")
    args = parser.parse_args()

    rows = []
    for path in tracked_or_nix_files():
        rows.extend(scan_file(path))
    rows.sort(key=lambda row: (row["file"], row["line"], row["package"]))

    if args.json:
        print(json.dumps(rows, indent=2))
        return

    print("package | file:line | note")
    for row in rows:
        location = f"{row['file']}:{row['line']}"
        print(f"{row['package']} | {location} | {row['note']}")


if __name__ == "__main__":
    main()
