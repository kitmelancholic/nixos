"""campaign-tui: run and watch scripts/campaign from one screen.

A live diagram of the autopilot loop sits in the middle and lights up the
step the campaign is on; around it the running attempt (quest, tier, CLI,
model, attempt, time, silence, context, cost, trace markers), the Claude
quota, and tabs with the agent's steps, its thoughts, the campaign's own
output, runs.tsv and the squire's diagnosis.

The campaign runs unchanged inside a pseudo-terminal: its y/n and one-line
questions open a dialog here, and the answer is typed into that terminal.
A campaign started elsewhere is only watched. Everything else is read from
docs/tasks.md, docs/progress.md, .agents/models.md and .campaign/; nothing
is written. Started by scripts/campaign-tui.
"""

from __future__ import annotations

import asyncio
import codecs
import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import termios
import time
from dataclasses import dataclass, field
from pathlib import Path

from rich.text import Text
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.command import DiscoveryHit, Hit, Hits, Provider
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.screen import ModalScreen
from textual.widgets import (
    Button,
    Footer,
    Input,
    Label,
    RichLog,
    Select,
    Sparkline,
    Static,
    TabbedContent,
    TabPane,
)

def toplevel() -> Path:
    try:
        return Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip())
    except (OSError, subprocess.CalledProcessError):
        return Path.cwd()


ROOT = Path(os.environ.get("CAMPAIGN_TUI_ROOT") or toplevel())
CAMPAIGN = ROOT / ".campaign"
USAGE = Path(
    os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache"
) / "dangonix/claude-usage.json"
IDLE_MAX = 0
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][0-9A-Za-z]|\r")
LOG_NAME = re.compile(r"^(c\d+[qs]\d+)\.(\d+)\.json$")


def seconds(v: str) -> int:
    m = re.fullmatch(r"(\d+)([hms]?)", v.strip())
    if not m:
        return 1200
    return int(m[1]) * {"h": 3600, "m": 60, "s": 1, "": 1}[m[2]]


IDLE_LIMIT = os.environ.get("QUEST_IDLE", "20m")
IDLE_MAX = seconds(IDLE_LIMIT)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def k(n: float | int | None) -> str:
    if not n:
        return "0"
    return f"{n / 1000:.1f}k" if n >= 1000 else str(int(n))


def clock(s: float) -> str:
    s = max(0, int(s))
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60}:{s % 60:02d}"


def bar(val: float, top: float, n: int = 12) -> Text:
    frac = 0.0 if top <= 0 else min(1.0, max(0.0, val / top))
    full = round(frac * n)
    colour = "red" if frac >= 0.9 else "yellow" if frac >= 0.7 else "green"
    t = Text("▕", style="dim")
    t.append("█" * full, style=colour)
    t.append("░" * (n - full), style="dim")
    t.append("▏", style="dim")
    return t


TIERS = {
    "squire": ("◆", "green"),
    "hero": ("⚔", "cyan"),
    "cleric": ("✚", "magenta"),
    "judge": ("⚖", "blue"),
}

# --- the campaign's files -------------------------------------------------


@dataclass
class Quest:
    id: str
    name: str
    boss: bool
    rest: str
    tier: str
    effort: str
    state: str = ""


def quests() -> list[Quest]:
    out: list[Quest] = []
    lines = read(ROOT / "docs/tasks.md").splitlines()
    for i, line in enumerate(lines):
        m = re.match(r"^## (c\d+[qs]\d+) - (.*)$", line)
        if not m:
            continue
        meta = lines[i + 1] if i + 1 < len(lines) else ""
        get = lambda key: (re.search(rf"\b{key}=(\S+)", meta) or [None, ""])[1]  # noqa: E731
        name = m[2].replace("⚔️", "").replace("⚔", "").strip()
        out.append(Quest(m[1], name, "⚔" in m[2], get("rest"), get("tier"), get("effort")))
    states = {}
    for m in re.finditer(r"^## (c\d+[qs]\d+) - (.+)$", read(ROOT / "docs/progress.md"), re.M):
        states[m[1]] = m[2].strip()
    for q in out:
        q.state = states.get(q.id, "")
    return out


def model_limits() -> dict[str, dict[str, int]]:
    rows: dict[str, dict[str, int]] = {}
    head: list[str] = []
    for line in read(ROOT / ".agents/models.md").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if not line.startswith("|") or set("".join(cells)) <= set("-: "):
            continue
        if cells[0] == "tier":
            head = cells
            continue
        if head:
            rows[cells[0]] = {h: int(c) for h, c in zip(head, cells) if c.isdigit()}
    return rows


def model_name(agent: str, tier: str) -> str:
    """The model .agents/models.md gives an agent's tier."""
    head: list[str] = []
    for line in read(ROOT / ".agents/models.md").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0] == "tier":
            head = cells
        elif head and cells[0] == tier and agent in head:
            return cells[head.index(agent)]
    return ""


def runs() -> list[list[str]]:
    return [l.split("\t") for l in read(CAMPAIGN / "runs.tsv").splitlines() if l.count("\t") >= 10]


def attempt_logs() -> list[Path]:
    try:
        logs = [p for p in CAMPAIGN.iterdir() if LOG_NAME.match(p.name)]
    except OSError:
        return []
    return sorted(logs, key=lambda p: p.stat().st_mtime)


@dataclass
class Proc:
    pid: int
    argv: list[str]


def processes() -> tuple[Proc | None, Proc | None]:
    """The running scripts/campaign and scripts/agent (run beats ask)."""
    campaign = agent = None
    for d in Path("/proc").iterdir():
        if not d.name.isdigit():
            continue
        try:
            argv = (d / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        argv = [a.decode(errors="replace") for a in argv if a]
        if len(argv) < 2 or not argv[0].endswith("bash"):
            continue
        if argv[1].endswith("scripts/campaign"):
            campaign = Proc(int(d.name), argv)
        elif argv[1].endswith("scripts/agent") and len(argv) >= 7 and argv[2] in ("run", "ask"):
            if agent is None or (argv[2] == "run" and agent.argv[2] == "ask"):
                agent = Proc(int(d.name), argv)
    return campaign, agent


def proc_age(pid: int) -> float:
    try:
        start = int((Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split())[19])
        boot = float(Path("/proc/uptime").read_text().split()[0])
        return boot - start / os.sysconf("SC_CLK_TCK")
    except (OSError, ValueError, IndexError):
        return 0.0


# --- one attempt's log ----------------------------------------------------


@dataclass
class Step:
    tool: str
    text: str
    kind: str
    ok: bool | None = None
    lines: int = 0
    mark: str = ""


@dataclass
class Attempt:
    path: Path
    offset: int = 0
    steps: list[Step] = field(default_factory=list)
    words: list[tuple[str, str]] = field(default_factory=list)
    pending: dict[str, Step] = field(default_factory=dict)
    model: str = ""
    ctx: int = 0
    out_tok: int = 0
    cost: float | None = None
    first: float = 0.0
    last: float = 0.0
    ended: str = ""
    codex: bool = False
    limits: dict[str, dict] = field(default_factory=dict)
    ctx_hist: list[int] = field(default_factory=list)
    trace_size: int = -1
    summary: list[str] = field(default_factory=list)

    def update(self) -> None:
        try:
            with self.path.open("rb") as f:
                f.seek(self.offset)
                data = f.read()
        except OSError:
            return
        end = data.rfind(b"\n") + 1
        self.offset += end
        for raw in data[:end].splitlines():
            try:
                e = json.loads(raw)
            except ValueError:
                continue
            if isinstance(e, dict):
                self.event(e)
        self.markers()

    def event(self, e: dict) -> None:
        ts = e.get("_ts") or 0
        if ts:
            self.first = self.first or ts
            self.last = ts
        t = e.get("type")
        if e.get("subtype") == "init":
            self.model = e.get("model", "")
        if t == "rate_limit_event":
            info = e.get("rate_limit_info") or {}
            self.limits[info.get("rateLimitType", "?")] = info | {"_ts": ts}
        elif t == "assistant" and not e.get("parent_tool_use_id"):
            msg = e.get("message") or {}
            u = msg.get("usage") or {}
            ctx = sum(u.get(x, 0) or 0 for x in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
            if ctx and ctx != self.ctx:
                self.ctx_hist.append(ctx)
            self.ctx = ctx or self.ctx
            self.out_tok += u.get("output_tokens", 0) or 0
            for c in msg.get("content") or []:
                ct = c.get("type")
                if ct == "thinking" and c.get("thinking"):
                    self.words.append(("💭", c["thinking"]))
                elif ct == "text" and c.get("text"):
                    self.words.append(("✎", c["text"]))
                elif ct == "tool_use":
                    inp = c.get("input") or {}
                    name = c.get("name", "?")
                    text = inp.get("command") or rel(inp.get("file_path", "")) or inp.get("pattern") or json.dumps(inp, ensure_ascii=False)
                    s = Step(name, " ".join(str(text).split()), kind_of(name, str(text)))
                    self.steps.append(s)
                    self.pending[c.get("id", "")] = s
                    self.words.append(("▸", f"{name} {s.text}"))
        elif t == "user":
            for c in (e.get("message") or {}).get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    s = self.pending.pop(c.get("tool_use_id", ""), None)
                    if s:
                        s.ok = not c.get("is_error")
                        s.lines = nlines(body(c.get("content")))
        elif t == "result":
            self.cost = e.get("total_cost_usd")
            self.ended = e.get("subtype", "?")
        elif t == "turn.completed":
            u = e.get("usage") or {}
            self.ctx = u.get("input_tokens", self.ctx)
            self.out_tok = u.get("output_tokens", self.out_tok)
            self.ended = "хід завершено"
        elif t in ("thread.started", "turn.started"):
            self.codex = True
        elif t == "item.completed":
            self.codex = True
            it = e.get("item") or {}
            it_t = it.get("type")
            if it_t == "reasoning" and it.get("text"):
                self.words.append(("💭", it["text"]))
            elif it_t == "agent_message" and it.get("text"):
                self.words.append(("✎", it["text"]))
            elif it_t == "command_execution":
                cmd = unwrap(it.get("command", ""))
                s = Step("shell", cmd, kind_of("shell", cmd), (it.get("exit_code") or 0) == 0, nlines(it.get("aggregated_output") or ""))
                self.steps.append(s)
                self.words.append(("▸", f"shell {cmd}"))
            elif it_t == "file_change":
                paths = ", ".join(rel(c.get("path", "")) for c in it.get("changes") or [])
                self.steps.append(Step("patch", paths, "write", it.get("status") != "failed"))
                self.words.append(("▸", f"patch {paths}"))
            elif it_t == "mcp_tool_call":
                s = Step("mcp", f"{it.get('server')}/{it.get('tool')}", "read", it.get("status") != "failed")
                self.steps.append(s)

    def markers(self) -> None:
        """scripts/trace's markers per step and its patterns line."""
        size = self.offset
        if size == self.trace_size or not self.steps:
            return
        self.trace_size = size
        try:
            out = subprocess.run(
                ["jq", "-rs", "--arg", "mode", "trace", "-f", str(ROOT / "scripts/trace.jq"), str(self.path)],
                capture_output=True, text=True, timeout=20,
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return
        n = 0
        self.summary = []
        for line in out.splitlines():
            if line.startswith("#"):
                n += 1
                if n <= len(self.steps):
                    tail = line.split("рядк.", 1)[-1]
                    self.steps[n - 1].mark = re.sub(r"^\s*~\S+", "", tail).strip()
            elif line.startswith(("патерни:", "найважчі", "відмови", "найдовш")):
                self.summary.append(line)

    def stage(self) -> int:
        """Which step of the quest procedure the agent is on (1-7)."""
        st = 1
        for i, s in enumerate(self.steps):
            t = s.text
            if re.search(r"\bgit tag\b|next-version", t):
                st = 7
            elif re.search(r"\bgit commit\b", t):
                st = 6
            elif "scripts/review" in t:
                st = 5
            elif "quest-verify" in t:
                st = 4
            elif s.kind == "write" or re.search(r"nix fmt|check --fast|dangonix check", t):
                st = 3
            elif st < 3:
                st = 1 if i < 4 else 2
        return st


def rel(p: str) -> str:
    return re.sub(r"^/.*?/nixos/", "", p or "")


def unwrap(c: str) -> str:
    c = re.sub(r"^(/usr/bin/env )?(ba)?sh -l?c ", "", c)
    c = re.sub(r"^'(.*)'$", r"\1", c)
    return " ".join(re.sub(r'^"(.*)"$', r"\1", c).split())


def body(c) -> str:
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict))
    return "" if c is None else str(c)


def nlines(s: str) -> int:
    return len(s.rstrip("\n").split("\n")) if s else 0


READ = re.compile(r"^(cat|head|tail|less|grep|rg|ls|find|fd|tree|wc|awk|jq|sed -n|git (show|log|diff|status|grep|ls-files|blame)|nix (eval|derivation show|path-info|search|flake (show|metadata))|scripts/opt)\b")


def kind_of(tool: str, text: str) -> str:
    if re.match(r"^(Read|Grep|Glob|LS|WebFetch|WebSearch)$", tool):
        return "read"
    if re.match(r"^(Edit|Write|MultiEdit|NotebookEdit)$", tool):
        return "write"
    return "read" if READ.match(text) else "cmd"


# --- the Claude quota ------------------------------------------------------


def quota(attempts: list[Attempt]) -> dict[str, dict]:
    """five_hour and seven_day: {pct, resets, ts, src}. The statusline
    snapshot (scripts/claude-statusline) has percentages; a campaign log's
    rate_limit_event has the status, the reset time and sometimes the
    utilization."""
    out: dict[str, dict] = {}
    try:
        snap = json.loads(USAGE.read_text())
        for key in ("five_hour", "seven_day"):
            v = (snap.get("rate_limits") or {}).get(key)
            if v:
                out[key] = {"pct": v.get("used_percentage"), "resets": v.get("resets_at"), "ts": snap.get("ts", 0), "src": "statusline"}
    except (OSError, ValueError):
        pass
    for a in attempts:
        for key, info in a.limits.items():
            ts = info.get("_ts", 0)
            if key in out and out[key]["ts"] >= ts:
                continue
            resets = info.get("resetsAt")
            if resets and resets > 10**11:
                resets /= 1000
            util = info.get("utilization")
            prev = out.get(key, {})
            out[key] = {
                "pct": util * 100 if util is not None else prev.get("pct"),
                "resets": resets or prev.get("resets"),
                "ts": ts,
                "status": info.get("status"),
                "src": "campaign",
            }
    return out


# --- the diagram -----------------------------------------------------------

# Boxes are found by their first label; fields are runs of @ (the name is
# the first word after the @).
DIAGRAM = r"""
┌──────────────┐    ┌───────────────────┐    ┌──────────────────┐             ╔══════════════════════════╗
│ Старт        │───▶│ Наступний квест   │───▶│ Що в журналі?    │── чекає ───▶║ Майстер                  ║
│ @run@@@@@@@@ │    │ @next@@@@@@@@@@@@ │    │ @jst@@@@@@@@@@@@ │             ╟──────────────────────────╢
└──────────────┘    └───────────────────┘    └──────────────────┘             ║ запит: скоуп / дозвіл    ║
       ▲                                              │ новий / ретрай        ║ ⚖ суддя радить, ти y/n   ║
       │                                              ▼                       ╟──────────────────────────╢
       │      ┌──────────────────────────────────────────────────────┐        ║ хід майстра              ║
       │      │ Агент @agent@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ │        ║ чекліст → y / n          ║
       │      │ 1 Читає → 2 Передумови → 3 Кроки ⟲ → 4 quest-verify  │        ╟──────────────────────────╢
       │      │ → 5 Суддя ⚔ → 6 Коміт → 7 Long rest                  │        ║ інший кидок              ║
       │      │ @step@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ │        ║ рішення → клерик         ║
       │      └──────────────────────────────────────────────────────┘        ╚══════════════════════════╝
       │                                │                                                  │
       │                                ▼                                                  │
       │                     ┌────────────────────┐      ┌──────────────────────┐          │
       │                     │ Що вийшло?         │─────▶│ ◆ Діагноз сквайра    │          │
       │                     │ @out@@@@@@@@@@@@@@ │      │ @diag@@@@@@@@@@@@@@@ │          │
       │                     └────────────────────┘      └──────────────────────┘          │
       │          ┌─────────────────────┼─────────────────────────┐                        │
       │          ▼                     ▼                         ▼                        │
       │   ┌──────────────┐     ┌────────────────┐       ┌────────────────┐                │
       ├───│ ✓ Запис      │     │ ↻ Без запису   │       │ ⏱ Таймаут      │                │
       │   │ і коміт      │     │ 1 перезапуск   │       │ стоп кампанії  │                │
       │   └──────────────┘     └────────────────┘       └────────────────┘                │
       └────────────────── відповідь у журнал і коміт, нове коло ◀─────────────────────────┘
""".strip("\n").splitlines()

BOXES = {
    "start": "Старт",
    "next": "Наступний квест",
    "journal": "Що в журналі?",
    "gm": "Майстер",
    "agent": "Агент",
    "outcome": "Що вийшло?",
    "diag": "◆ Діагноз сквайра",
    "done": "✓ Запис",
    "rerun": "↻ Без запису",
    "timeout": "⏱ Таймаут",
}
SPANS = {
    "gm_request": ["запит: скоуп / дозвіл", "⚖ суддя радить, ти y/n"],
    "gm_turn": ["хід майстра", "чекліст → y / n"],
    "gm_decision": ["інший кидок", "рішення → клерик"],
    1: ["1 Читає"],
    2: ["2 Передумови"],
    3: ["3 Кроки ⟲"],
    4: ["4 quest-verify"],
    5: ["5 Суддя ⚔"],
    6: ["6 Коміт"],
    7: ["7 Long rest"],
}
SPIN = "◐◓◑◒"


def find(label: str) -> tuple[int, int]:
    for r, line in enumerate(DIAGRAM):
        c = line.find(label)
        if c >= 0:
            return r, c
    raise KeyError(label)


def box_rect(label: str) -> tuple[int, int, int, int]:
    r, c = find(label)
    line = DIAGRAM[r]
    left = max(line.rfind("│", 0, c), line.rfind("║", 0, c))
    right_a = [x for x in (line.find("│", c), line.find("║", c)) if x >= 0]
    right = min(right_a)
    top = r
    while top > 0 and DIAGRAM[top - 1][left : left + 1] not in ("┌", "╔"):
        top -= 1
    top -= 1
    bottom = r
    while bottom + 1 < len(DIAGRAM) and DIAGRAM[bottom + 1][left : left + 1] not in ("└", "╚"):
        bottom += 1
    bottom += 1
    return top, bottom, left, right


RECTS = {key: box_rect(label) for key, label in BOXES.items()}
FIELDS: dict[str, tuple[int, int, int]] = {}
for _r, _line in enumerate(DIAGRAM):
    for _m in re.finditer(r"@(\w+)@*", _line):
        FIELDS[_m[1]] = (_r, _m.start(), _m.end() - _m.start())


# Arrows, traced cell by cell from where they leave a box to their head.
MOVES = {"E": (0, 1), "W": (0, -1), "S": (1, 0), "N": (-1, 0)}
TURNS = {
    ("┐", "E"): "S", ("┘", "E"): "N", ("┘", "S"): "W", ("└", "S"): "E",
    ("└", "W"): "N", ("┌", "W"): "S", ("┌", "N"): "E", ("├", "W"): "N",
}


def trace_edge(r: int, c: int, d: str) -> list[tuple[int, int]]:
    path = []
    while 0 <= r < len(DIAGRAM) and 0 <= c < len(DIAGRAM[r]) and len(path) < 300:
        ch = DIAGRAM[r][c]
        path.append((r, c))
        if ch in "▶▼▲":
            break
        d = TURNS.get((ch, d), d)
        dr, dc = MOVES[d]
        r, c = r + dr, c + dc
    return path


def below(key: str, ch: str = "│") -> tuple[int, int]:
    top, bottom, left, right = RECTS[key]
    return bottom + 1, DIAGRAM[bottom + 1].index(ch, left, right)


def right_of(key: str) -> tuple[int, int]:
    top, _, _, right = RECTS[key]
    return top + 1, right + 1


EDGES = {
    "start>next": trace_edge(*right_of("start"), "E"),
    "next>journal": trace_edge(*right_of("next"), "E"),
    "journal>gm": trace_edge(*right_of("journal"), "E"),
    "journal>agent": trace_edge(*below("journal"), "S"),
    "agent>outcome": trace_edge(*below("agent"), "S"),
    "outcome>diag": trace_edge(*right_of("outcome"), "E"),
    "outcome>done": trace_edge(*below("outcome", "┼"), "W"),
    "outcome>rerun": trace_edge(below("outcome", "┼")[0] + 1, below("outcome", "┼")[1], "S"),
    "outcome>timeout": trace_edge(*below("outcome", "┼"), "E"),
    "gm>loop": trace_edge(*below("gm"), "S"),
    "done>loop": trace_edge(RECTS["done"][0] + 1, RECTS["done"][2] - 1, "W"),
}
# Which arrows lead into each box.
INTO = {
    "next": ["start>next"],
    "journal": ["next>journal"],
    "gm": ["journal>gm"],
    "agent": ["journal>agent"],
    "outcome": ["agent>outcome"],
    "diag": ["outcome>diag"],
    "done": ["outcome>done"],
    "rerun": ["outcome>rerun"],
    "timeout": ["outcome>timeout"],
}


def render_diagram(active: set, trail: set, step: int | None, values: dict[str, str], tick: int, phase: int = 0) -> Text:
    rows = [list(line) for line in DIAGRAM]
    for name, (r, c, n) in FIELDS.items():
        v = values.get(name, "")[:n].ljust(n)
        rows[r][c : c + n] = list(v)
    width = max(len(r) for r in rows)
    styles = [[""] * width for _ in rows]

    def paint(key, style, rect=None):
        top, bottom, left, right = rect or RECTS[key]
        for r in range(top, bottom + 1):
            for c in range(left, min(right + 1, len(rows[r]))):
                styles[r][c] = style

    for key in RECTS:
        paint(key, "dim")
    for key in trail & RECTS.keys():
        paint(key, "green")
    for key in active & RECTS.keys():
        paint(key, "bold yellow" if key == "gm" else "bold cyan")
    spans = [s for s in active if s in SPANS] + ([step] if step else [])
    for key in spans:
        for label in SPANS[key]:
            r, c = find(label)
            for x in range(c, c + len(label)):
                styles[r][x] = "bold black on yellow" if str(key).startswith("gm") else "bold black on cyan"
    if step:
        for done in range(1, step):
            r, c = find(SPANS[done][0])
            for x in range(c, c + len(SPANS[done][0])):
                styles[r][x] = "green"
    # A comet runs along every arrow into the active box (and around the
    # loop when the round was closed by the GM or a commit).
    flows = [e for key in active for e in INTO.get(key, [])]
    if "next" in active or "start" in active:
        flows += [e for key, e in (("gm", "gm>loop"), ("done", "done>loop")) if key in trail]
    hot = "bold yellow" if "gm" in active else "bold cyan"
    for e in flows:
        path = EDGES[e]
        head = phase % (len(path) + 4)
        for i, (r, c) in enumerate(path):
            if head - 3 <= i <= head:
                styles[r][c] = hot if i == head else hot.replace("bold ", "")
                if i == head and rows[r][c] in "─│┼├┐┘└┌":
                    rows[r][c] = "●"
            elif styles[r][c] == "":
                styles[r][c] = "dim"
    # A spinner in the corner of the active box.
    for key in active & RECTS.keys():
        top, _, _, right = RECTS[key]
        rows[top][right - 2] = SPIN[tick % 4]
    out = Text()
    for r, line in enumerate(rows):
        for c, ch in enumerate(line):
            out.append(ch, style=styles[r][c] if c < width else "")
        if r < len(rows) - 1:
            out.append("\n")
    return out


# --- screens ---------------------------------------------------------------


class Ask(ModalScreen[str | None]):
    """The campaign asks the GM: y/n or one line."""

    BINDINGS = [Binding("escape", "dismiss(None)", "пізніше")]

    def __init__(self, question: str, context: str, yesno: bool) -> None:
        super().__init__()
        self.question, self.context, self.yesno = question, context, yesno

    def compose(self) -> ComposeResult:
        with Vertical(id="ask"):
            yield Label("⚑ хід майстра", id="ask-title")
            with VerticalScroll(id="ask-context"):
                yield Static(Text(self.context))
            yield Label(Text(self.question, style="bold"))
            if self.yesno:
                with Horizontal(id="ask-buttons"):
                    yield Button("y · так", id="y", variant="success")
                    yield Button("n · ні", id="n", variant="error")
            else:
                yield Input(placeholder="одним рядком; порожньо = стоп", id="ask-input")

    def on_mount(self) -> None:
        self.query_one("#ask-context").scroll_end(animate=False)
        if not self.yesno:
            self.query_one(Input).focus()

    def on_key(self, event) -> None:
        if self.yesno and event.key in ("y", "n"):
            self.dismiss(event.key)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value)


class Start(ModalScreen[list[str] | None]):
    BINDINGS = [Binding("escape", "dismiss(None)", "назад")]

    def compose(self) -> ComposeResult:
        with Vertical(id="ask"):
            yield Label("Почати кампанію", id="ask-title")
            yield Label("Герой (--agent)")
            yield Select([("claude", "claude"), ("codex", "codex")], value="claude", allow_blank=False, id="agent")
            yield Label("Суддя (--judge)")
            yield Select([("як герой", ""), ("claude", "claude"), ("codex", "codex")], value="", allow_blank=False, id="judge")
            with Horizontal(id="ask-buttons"):
                yield Button("▶ у бій", id="go", variant="success")
                yield Button("назад", id="back")

    def on_mount(self) -> None:
        self.query_one("#go", Button).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id != "go":
            self.dismiss(None)
            return
        args = ["--agent", self.query_one("#agent", Select).value]
        judge = self.query_one("#judge", Select).value
        if judge:
            args += ["--judge", judge]
        self.dismiss(args)


class Confirm(ModalScreen[bool]):
    BINDINGS = [Binding("escape", "dismiss(False)", "ні")]

    def __init__(self, text: str) -> None:
        super().__init__()
        self.text = text

    def compose(self) -> ComposeResult:
        with Vertical(id="ask"):
            yield Label(self.text)
            with Horizontal(id="ask-buttons"):
                yield Button("y · так", id="y", variant="error")
                yield Button("n · ні", id="n")

    def on_key(self, event) -> None:
        if event.key in ("y", "n"):
            self.dismiss(event.key == "y")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "y")


# --- the app ---------------------------------------------------------------


class Banner(ModalScreen[None]):
    """A new quest: its id in big letters for a few seconds."""

    def __init__(self, quest: str, name: str, line: str) -> None:
        super().__init__()
        self.quest, self.name_, self.line = quest, name, line

    def compose(self) -> ComposeResult:
        try:
            import pyfiglet

            big = pyfiglet.figlet_format(self.quest.upper(), font="ansi_shadow").rstrip("\n ")
        except Exception:  # noqa: BLE001  # a plain banner is fine
            big = self.quest.upper()
        t = Text(justify="center")
        t.append("✦ новий квест ✦\n\n", style="dim")
        t.append(big + "\n\n", style="bold cyan")
        t.append(self.name_ + "\n", style="bold")
        t.append(self.line, style="dim")
        with Vertical(id="banner"):
            yield Static(t)

    def on_mount(self) -> None:
        self.set_timer(4, self.close)

    def close(self) -> None:
        if self.is_current:
            self.dismiss(None)

    def on_key(self, event) -> None:
        self.close()


class Commands(Provider):
    """Ctrl+P: the campaign's own commands."""

    def items(self):
        app = self.app
        return [
            ("Почати кампанію", "s · герой і суддя на вибір", app.action_start),
            ("Зупинити кампанію", "x · Ctrl+C у campaign", app.action_stop),
            ("Відповісти на питання campaign", "a · знову відкрити діалог", app.action_answer),
            ("Trace спроби в less", "scripts/trace поточного логу", lambda: app.pager("trace")),
            ("Діагноз сквайра в less", ".campaign/<id>.diagnosis.md", lambda: app.pager("diagnosis")),
            ("Сирий лог спроби в less", ".campaign/<id>.<n>.json, jq", lambda: app.pager("log")),
            ("Розділ квесту з tasks.md в less", "## <id> у docs/tasks.md", lambda: app.pager("quest")),
            ("Скопіювати останню команду агента", "у буфер обміну (OSC 52)", app.copy_last),
            ("Уроки для писаря в less", ".campaign/lessons.md", lambda: app.pager("lessons")),
        ]

    async def discover(self) -> Hits:
        for name, help_, cb in self.items():
            yield DiscoveryHit(name, cb, help=help_)

    async def search(self, query: str) -> Hits:
        matcher = self.matcher(query)
        for name, help_, cb in self.items():
            score = matcher.match(name)
            if score > 0:
                yield Hit(score, matcher.highlight(name), cb, help=help_)


class CampaignTUI(App):
    TITLE = "dangoNix"
    COMMANDS = App.COMMANDS | {Commands}
    CSS = """
    Screen { layout: vertical; }
    #top { height: auto; padding: 0 1; }
    #middle { height: auto; }
    .panel { border: round $panel-lighten-2; border-title-color: $text-muted;
             border-title-style: bold; padding: 0 1; height: auto; }
    .panel.hot { border: round $warning; border-title-color: $warning; }
    .panel.live { border: round $accent; border-title-color: $accent; }
    #diagram-wrap { width: auto; max-width: 100%; overflow-x: auto; height: auto; }
    #diagram { width: auto; }
    #right { width: 1fr; min-width: 36; height: auto; }
    #ctx-spark { height: 3; }
    #timeline { height: auto; }
    Banner { align: center middle; background: $background 60%; }
    #banner { width: auto; height: auto; padding: 1 4; border: double $accent; background: $surface; }
    TabbedContent { height: 1fr; }
    RichLog, VerticalScroll.tab { height: 1fr; }
    #ask { width: 90; max-width: 95%; height: auto; max-height: 90%; padding: 1 2;
           border: thick $warning; background: $surface; }
    #ask-title { text-style: bold; color: $warning; }
    #ask-context { height: auto; max-height: 24; margin: 1 0; border: round $panel; }
    #ask-buttons { height: auto; margin-top: 1; }
    #ask-buttons Button { margin-right: 2; }
    Ask, Start, Confirm { align: center middle; }
    """
    BINDINGS = [
        Binding("s", "start", "почати"),
        Binding("x", "stop", "зупинити"),
        Binding("a", "answer", "відповісти"),
        Binding("1", "tab('steps')", "кроки"),
        Binding("2", "tab('words')", "думки"),
        Binding("3", "tab('out')", "campaign"),
        Binding("4", "tab('runs')", "спроби"),
        Binding("5", "tab('story')", "діагноз"),
        Binding("left_square_bracket", "older", "старіша"),
        Binding("right_square_bracket", "newer", "новіша"),
        Binding("0", "live", "наживо", show=False),
        Binding("q", "quit_tui", "вийти"),
    ]

    def __init__(self) -> None:
        # The terminal's own 16 colours: Ghostty's Manuscript, dark or light.
        super().__init__(ansi_color=True)
        self.attempts: dict[Path, Attempt] = {}
        self.pick = 0
        self.tick = 0
        self.master: int | None = None
        self.proc: subprocess.Popen | None = None
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.partial = ""
        self.out_lines: list[str] = []
        self.prompt: tuple[str, str, bool] | None = None
        self.asking = False
        self.event = ""  # what the campaign's own output said last
        self.trail: set[str] = set()
        self.limits = model_limits()
        self.words_shown = (None, 0)
        self.steps_shown = (None, 0, "")
        self.belled = False
        self.runs_seen = -1
        self.phase = 0
        self.diag_args: tuple | None = None
        self.current: Attempt | None = None
        self.bannered: str | None = None

    def compose(self) -> ComposeResult:
        yield Static(id="top")
        with Horizontal(id="middle"):
            with Vertical(id="diagram-wrap", classes="panel"):
                yield Static(id="diagram")
            with Vertical(id="right"):
                yield Static(id="side", classes="panel")
                yield Sparkline([], id="ctx-spark", classes="panel", summary_function=max)
                yield Static(id="quota", classes="panel")
        yield Static(id="timeline", classes="panel")
        with TabbedContent(initial="steps"):
            with TabPane("1 кроки", id="steps"):
                yield RichLog(id="steps-log", wrap=False, markup=False)
            with TabPane("2 думки", id="words"):
                yield RichLog(id="words-log", wrap=True, markup=False)
            with TabPane("3 campaign", id="out"):
                yield RichLog(id="out-log", wrap=True, markup=False)
            with TabPane("4 спроби", id="runs"):
                yield RichLog(id="runs-log", wrap=False, markup=False)
            with TabPane("5 діагноз", id="story"):
                yield RichLog(id="story-log", wrap=True, markup=False)
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#diagram-wrap").border_title = "цикл кампанії"
        self.query_one("#ctx-spark").border_title = "ріст контексту"
        self.query_one("#quota").border_title = "Claude Pro"
        self.query_one("#timeline").border_title = "сьогодні"
        self.set_interval(0.12, self.animate)
        self.follow_look()
        self.refresh_all()
        self.set_interval(1, self.refresh_all)
        self.set_interval(30, self.follow_look)

    def follow_look(self) -> None:
        """Dark or light like the desktop (dangonix.look sets color-scheme)."""
        try:
            scheme = subprocess.run(
                ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
                capture_output=True, text=True, timeout=2,
            ).stdout
        except (OSError, subprocess.SubprocessError):
            scheme = ""
        theme = "ansi-light" if "light" in scheme else "ansi-dark"
        if self.theme != theme:
            self.theme = theme

    # --- the campaign in a pseudo-terminal

    def action_start(self) -> None:
        campaign, _ = processes()
        if self.proc and self.proc.poll() is None or campaign:
            self.notify("campaign уже йде", severity="warning")
            return
        self.push_screen(Start(), self.spawn)

    def spawn(self, args: list[str] | None) -> None:
        if args is None:
            return
        master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, b"\x00\x28\x00\x78\x00\x00\x00\x00")  # 40x120

        def tty() -> None:
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        self.proc = subprocess.Popen(
            [str(ROOT / "scripts/campaign"), *args],
            cwd=ROOT, stdin=slave, stdout=slave, stderr=slave,
            start_new_session=True, preexec_fn=tty, close_fds=True,
        )
        os.close(slave)
        self.master = master
        self.out_lines.clear()
        self.query_one("#out-log", RichLog).clear()
        self.event = "start"
        self.trail = {"start"}
        asyncio.get_running_loop().add_reader(master, self.on_pty)
        self.notify("кампанія почалась: " + " ".join(args))

    def on_pty(self) -> None:
        try:
            data = os.read(self.master, 65536)
        except OSError:
            data = b""
        if not data:
            self.close_pty()
            return
        text = ANSI.sub("", self.decoder.decode(data))
        lines = (self.partial + text).split("\n")
        self.partial = lines.pop()
        log = self.query_one("#out-log", RichLog)
        for line in lines:
            self.out_lines.append(line)
            log.write(Text(line, style="yellow" if line.startswith("==") else ""))
            self.note(line)
        del self.out_lines[:-400]
        p = self.partial
        if re.search(r"(\[y/n\]|\(порожньо = стоп\):|одним рядком.*:)\s*$", p):
            self.prompt = (p.strip(), "\n".join(self.out_lines[-60:]), "[y/n]" in p)
            self.partial = ""
            log.write(Text(p, style="bold yellow"))
            self.ring()
            self.action_answer()

    def note(self, line: str) -> None:
        """Turn the campaign's own lines into diagram events."""
        if re.match(r"^== c\d+[qs]\d+ \(", line):
            self.event, self.trail = "agent", {"start", "next", "journal"}
        elif "diagnosis by the squire" in line:
            self.event = "diag"
        elif "one rerun on" in line:
            self.event = "rerun"
        elif "просить розширити" in line:
            self.event = "gm_request"
        elif re.match(r"^== c\d+[qs]\d+: хід майстра", line):
            self.event = "gm_turn"
        elif "timed out after" in line:
            self.event = "timeout"
        elif "Campaign complete" in line:
            self.event = "complete"
        elif re.match(r"^c\d+[qs]\d+: ", line) and self.event == "agent":
            self.event = "outcome"

    def close_pty(self) -> None:
        if self.master is not None:
            asyncio.get_running_loop().remove_reader(self.master)
            os.close(self.master)
            self.master = None
        if self.partial:
            self.out_lines.append(self.partial)
            self.query_one("#out-log", RichLog).write(self.partial)
            self.partial = ""
        self.prompt = None
        code = self.proc.wait() if self.proc else None
        self.notify(f"campaign закінчився ({code})")
        self.ring()

    def action_answer(self) -> None:
        if not self.prompt or self.asking:
            return
        question, context, yesno = self.prompt
        self.asking = True

        def done(answer: str | None) -> None:
            self.asking = False
            if answer is None or self.master is None:
                return
            os.write(self.master, (answer + "\n").encode())
            self.prompt = None

        self.push_screen(Ask(question, context, yesno), done)

    def action_stop(self) -> None:
        if not (self.proc and self.proc.poll() is None):
            campaign, _ = processes()
            self.notify("campaign запущено не тут: зупини його в його терміналі" if campaign else "campaign не йде")
            return

        def done(yes: bool) -> None:
            if yes and self.proc and self.proc.poll() is None:
                os.killpg(self.proc.pid, signal.SIGINT)

        self.push_screen(Confirm("Зупинити кампанію? (Ctrl+C: агент зупиниться, робота лишиться)"), done)

    def action_quit_tui(self) -> None:
        if self.proc and self.proc.poll() is None:

            def done(yes: bool) -> None:
                if yes:
                    os.killpg(self.proc.pid, signal.SIGINT)
                    try:
                        self.proc.wait(10)
                    except subprocess.TimeoutExpired:
                        pass
                    self.exit()

            self.push_screen(Confirm("Кампанія йде в цьому вікні. Зупинити її й вийти?"), done)
        else:
            self.exit()

    def ring(self) -> None:
        self.bell()

    # --- navigation

    def action_tab(self, tab: str) -> None:
        self.query_one(TabbedContent).active = tab

    def action_older(self) -> None:
        self.pick += 1
        self.refresh_all()

    def action_newer(self) -> None:
        self.pick = max(0, self.pick - 1)
        self.refresh_all()

    def action_live(self) -> None:
        self.pick = 0
        self.refresh_all()

    # --- drawing

    def attempt(self, path: Path) -> Attempt:
        a = self.attempts.setdefault(path, Attempt(path))
        a.update()
        return a

    def refresh_all(self) -> None:
        self.tick += 1
        now = time.time()
        qs = quests()
        campaign, agent = processes()
        mine = self.proc is not None and self.proc.poll() is None
        logs = attempt_logs()
        live_log = Path(ROOT / agent.argv[6]) if agent and agent.argv[2] == "run" else None
        if self.pick:
            self.pick = min(self.pick, max(0, len(logs) - 1))
            log = logs[len(logs) - 1 - self.pick] if logs else None
        else:
            log = live_log or (logs[-1] if logs else None)
        a = self.attempt(log) if log and log.exists() else None
        for p in logs[-5:]:
            self.attempt(p)

        # Where the campaign is.
        active: set = set()
        step = None
        if self.prompt:
            kind = "gm_request" if "Розширити" in self.prompt[0] else "gm_turn" if "чекліст" in self.prompt[0] else "gm_decision"
            active = {"gm", kind}
            status = Text("⚑ хід майстра: campaign чекає на твою відповідь (a)", style="bold yellow")
        elif agent and agent.argv[2] == "run":
            active = {"agent"}
            step = a.stage() if a and self.pick == 0 else None
            self.trail |= {"start", "next", "journal"}
            status = Text("● у бою", style="bold green")
        elif agent and agent.argv[3] == "squire":
            active, status = {"diag"}, Text("◆ сквайр пише діагноз", style="green")
            self.trail |= {"agent", "outcome"}
        elif agent:
            active, status = {"gm", "gm_request"}, Text("⚖ суддя зважує запит", style="blue")
        elif campaign or mine:
            ev = self.event
            if ev in ("gm_request", "gm_turn"):
                active = {"gm", ev}
            elif ev in ("rerun", "diag", "outcome"):
                active = {ev}
            elif ev == "agent":
                active = {"outcome"}
            elif not mine:
                active = {"gm"}
            else:
                active = {"next"}
            status = Text("● кампанія йде" + ("" if mine else " (в іншому терміналі)"), style="green")
            if not mine and not agent and not self.belled:
                status = Text("⚑ campaign чекає на тебе в його терміналі", style="bold yellow")
                self.ring()
                self.belled = True
        else:
            self.belled = False
            if self.event == "timeout":
                active = {"timeout"}
            elif self.event == "complete":
                active = {"done"}
            else:
                active = {"start"}
            status = Text("○ кампанія не йде · s почати", style="dim")
        if agent:
            self.belled = False
        if self.pick:
            status = Text(f"◂ архів: спроба {self.pick} з кінця (0 наживо)", style="blue")

        # The quest map.
        cur = None
        if a:
            cur = LOG_NAME.match(a.path.name)[1]
        nxt = next((q.id for q in qs if q.state != "виконано"), None)
        done = sum(q.state == "виконано" for q in qs)
        top = Text()
        top.append(" ⚔ dangoNix · кампанія ", style="bold")
        top.append_text(status)
        top.append(f"   {time.strftime('%H:%M:%S')}\n", style="dim")
        # Breadcrumbs: campaign › act › quest › attempt › step.
        crumbs = []
        if cur:
            idx = next((i for i, q in enumerate(qs) if q.id == cur), 0)
            act = sum(1 for q in qs[:idx] if q.rest)
            roman = "I II III IV V VI VII VIII IX X".split()
            crumbs = [f"Кампанія {roman[int(cur[1]) - 1] if cur[1].isdigit() else cur[1]}", f"акт {roman[act - 1] if 1 <= act <= 10 else act or 'пролог'}", cur]
            m = LOG_NAME.match(a.path.name)
            crumbs.append(f"кидок #{m[2]}")
            if step:
                crumbs.append(SPANS[step][0])
        for i, c in enumerate(crumbs):
            top.append(" › " if i else " ", style="dim")
            top.append(c, style="bold" if i == len(crumbs) - 1 else "")
        if crumbs:
            top.append("\n")
        top.append(f" мапа {done}/{len(qs)} ", style="bold")
        top.append_text(bar(done, len(qs), 10))
        top.append(" ")
        for q in qs:
            short = q.id[2:]
            sym, st = {
                "виконано": ("✓", "green"),
                "хід майстра": ("⚑", "yellow"),
                "провалений кидок": ("✗", "red"),
                "": ("·", "dim"),
            }.get(q.state, ("?", "yellow"))
            if q.id == cur:
                sym, st = "▶", "bold cyan"
            top.append(sym + short, style=st)
            if q.boss:
                top.append("☠", style="red")
            if q.rest:
                top.append("☾", style="dim")
            top.append(" ")
        self.query_one("#top", Static).update(top)

        # The diagram.
        quest = next((q for q in qs if q.id == cur), None)
        tier = agent.argv[4] if agent and agent.argv[2] == "run" and self.pick == 0 else ""
        row = None
        if a:
            m = LOG_NAME.match(a.path.name)
            row = next((r for r in reversed(runs()) if r[1] == m[1] and r[2] == m[2]), None)
            tier = tier or (row[5] if row else quest.tier if quest else "")
        icon, colour = TIERS.get(tier, ("?", "white"))
        n = LOG_NAME.match(a.path.name)[2] if a else ""
        values = {
            "run": "йде" if campaign or mine else "s · почати",
            "next": f"{nxt or '—'}",
            "jst": "",
            "agent": f"{icon} {tier} · {a.model or (row[4] if row else '') or model_name('codex' if a.codex else 'claude', tier)} · кидок #{n}" if a else "",
            "step": "",
            "out": "",
            "diag": "",
        }
        if nxt:
            qn = next(q for q in qs if q.id == nxt)
            values["jst"] = {"": "новий", "виконано": "виконано", "хід майстра": "чекає GM"}.get(qn.state, qn.state)
        if a and a.steps:
            last = a.steps[-1]
            values["step"] = f"#{len(a.steps)} {last.tool} {last.text}"
        if row:
            values["out"] = row[10]
        if (CAMPAIGN / f"{cur}.diagnosis.md").exists():
            values["diag"] = f"{cur}.diagnosis.md"
        if row and "done" not in active:
            outcome = row[10]
            if outcome.startswith("(no entry)") or outcome.startswith("(idle)"):
                self.trail.add("rerun")
            elif not active & {"agent"}:
                self.trail.add("done")
        self.diag_args = (active, self.trail - active, step, values)
        self.animate()
        self.current = a
        # A banner when a new attempt starts while the TUI watches.
        name = live_log.name if live_log else ""
        if self.bannered is None:
            self.bannered = name
        elif name and name != self.bannered:
            self.bannered = name
            if a and a.path == live_log and self.pick == 0:
                self.push_screen(Banner(cur, quest.name if quest else "", values["agent"]))
        wrap = self.query_one("#diagram-wrap")
        wrap.set_class("gm" in active, "hot")
        wrap.set_class("agent" in active, "live")
        wrap.border_title = "⚑ хід майстра" if "gm" in active else "цикл кампанії"
        wrap.border_subtitle = time.strftime("%H:%M:%S")

        # The side panel.
        side = Text()
        panel = self.query_one("#side", Static)
        panel.border_title = f"{cur} · кидок #{n}" if a else "спроба"
        panel.set_class(bool(agent and agent.argv[2] == "run" and self.pick == 0), "live")
        spark = self.query_one("#ctx-spark", Sparkline)
        spark.data = (a.ctx_hist[-60:] if a and a.ctx_hist else [0])
        spark.border_subtitle = k(a.ctx) if a else ""
        if a:
            side.append(f"{quest.name if quest else ''}\n", style="bold")
            side.append(f"{icon} {tier}", style=colour)
            side.append(f" · {'codex' if a.codex else 'claude'} · {quest.effort if quest else ''}\n", style="")
            side.append(f"{a.model or (row[4] if row else '')}\n", style="dim")
            live = live_log == a.path and self.pick == 0
            run_s = proc_age(agent.pid) if live and agent else (a.last - a.first)
            side.append("⏱ ", style="dim")
            side.append(clock(run_s), style="bold")
            side.append(f"   кидок #{n}\n")
            try:
                quiet = now - a.path.stat().st_mtime
            except OSError:
                quiet = 0
            side.append("тиша ", style="dim")
            side.append(clock(quiet) + " ")
            if live:
                side.append_text(bar(quiet, IDLE_MAX, 10))
                side.append(f" {IDLE_LIMIT}", style="dim")
            side.append("\n")
            lim = self.limits.get(tier, {})
            side.append("ctx  ", style="dim")
            side.append(k(a.ctx) + " ", style="bold")
            if lim.get("hard"):
                side.append_text(bar(a.ctx, lim["hard"], 10))
                side.append(f" {k(lim['hard'])}", style="dim")
                if lim.get("warn") and a.ctx >= lim["warn"]:
                    side.append(" стоп розвідка", style="yellow")
            side.append("\n")
            side.append(f"{len(a.steps)} кроків · вихід {k(a.out_tok)} ток.\n")
            cost = a.cost if a.cost is not None else (row[8] if row and row[8] != "-" else None)
            side.append("ціна ", style="dim")
            side.append(f"${float(cost):.2f}\n" if cost is not None else "у кінці\n", style="bold" if cost is not None else "dim")
            marks = [s.mark for s in a.steps if s.mark]
            if marks or any("цикл" in s for s in a.summary):
                counts = {ch: sum(ch in m for m in marks) for ch in "⟳↺▲⏱⏸"}
                side.append("⚠ " + " ".join(f"{ch}{c}" for ch, c in counts.items() if c), style="yellow")
                if any("цикл пошуку" in s for s in a.summary):
                    side.append(" цикл пошуку", style="yellow")
                side.append("\n")
            else:
                side.append("✓ без петель\n", style="green")
            if a.ended:
                side.append(f"⚑ {a.ended}\n", style="green")
        else:
            side.append("ще жодної спроби в .campaign/\n", style="dim")
        total = sum(float(r[8]) for r in runs() if re.fullmatch(r"[\d.]+", r[8]))
        side.append(f"\nскарбниця ${total:.2f} за {len(runs())} кидків\n", style="dim")
        self.query_one("#side", Static).update(side)
        side = Text()
        q = quota([self.attempts[p] for p in logs[-5:] if p in self.attempts])
        for key, label in (("five_hour", "сесія  "), ("seven_day", "тиждень")):
            v = q.get(key)
            side.append(label + " ", style="dim")
            if not v:
                side.append("—\n", style="dim")
                continue
            if v.get("pct") is not None:
                side.append_text(bar(v["pct"], 100, 10))
                side.append(f" {v['pct']:.0f}%", style="bold")
            elif v.get("status"):
                side.append(v["status"], style="red" if v["status"] == "rejected" else "yellow" if "warning" in v["status"] else "green")
            if v.get("resets"):
                left = v["resets"] - now
                lt = time.localtime(v["resets"])
                when = f"{int(left // 3600)}:{int(left % 3600 // 60):02d}" if left < 86400 else f"{'пн вт ср чт пт сб нд'.split()[lt.tm_wday]} {lt.tm_hour}:{lt.tm_min:02d}"
                side.append(f" ⟳{when}", style="dim")
            side.append("\n")
        if not q:
            side.append("немає даних: див. scripts/claude-statusline\n", style="dim")
        side.rstrip()
        self.query_one("#quota", Static).update(side)
        self.toast_runs()
        self.draw_timeline(now, live_log if self.pick == 0 else None, agent)
        self.fill_tabs(a)

    def animate(self) -> None:
        if self.diag_args:
            self.phase += 1
            active, trail, step, values = self.diag_args
            self.query_one("#diagram", Static).update(render_diagram(active, trail, step, values, self.phase // 8, self.phase))

    def draw_timeline(self, now: float, live: Path | None, agent: Proc | None) -> None:
        """Today's attempts as coloured runs on a time axis."""
        width = max(20, self.query_one("#timeline").size.width - 4)
        day = time.strftime("%Y-%m-%d")
        spans = []
        for r in runs():
            if not r[0].startswith(day):
                continue
            try:
                end = time.mktime(time.strptime(r[0], "%Y-%m-%dT%H:%M:%S"))
                mins = int(r[7].rstrip("m") or 0)
            except ValueError:
                continue
            colour = "green" if r[10] == "виконано" else "yellow" if r[10] == "хід майстра" else "red"
            spans.append((end - mins * 60 - 30, end, colour, r[1][2:]))
        if live and agent:
            spans.append((now - proc_age(agent.pid), now, "cyan", LOG_NAME.match(live.name)[1][2:]))
        t = Text()
        if not spans:
            t.append("сьогодні ще не було спроб", style="dim")
            self.query_one("#timeline", Static).update(t)
            return
        start = min(sp[0] for sp in spans)
        start -= start % 3600
        stop = max(now, start + 3600)
        scale = (stop - start) / width
        cells = [("·", "dim")] * width
        labels = [" "] * width
        for a, b, colour, label in spans:
            i, j = int((a - start) / scale), max(int((a - start) / scale) + 1, int((b - start) / scale))
            for x in range(i, min(j, width)):
                cells[x] = ("█", colour)
            for x, ch in enumerate(label[: max(0, min(j, width) - i)]):
                labels[i + x] = ch
        ticks = [" "] * width
        h = start
        while h < stop:
            x = int((h - start) / scale)
            for y, ch in enumerate(time.strftime("%H", time.localtime(h))):
                if x + y < width:
                    ticks[x + y] = ch
            h += 3600 if (stop - start) / 3600 <= width / 4 else 7200
        t.append("".join(ticks) + "\n", style="dim")
        for ch, st in cells:
            t.append(ch, style=st)
        t.append("\n" + "".join(labels), style="dim")
        self.query_one("#timeline", Static).update(t)

    def pager(self, what: str) -> None:
        a = self.current
        if not a:
            self.notify("немає спроби")
            return
        qid = LOG_NAME.match(a.path.name)[1]
        if what == "trace":
            cmd = f"scripts/trace {a.path} | less -R"
        elif what == "log":
            cmd = f"jq -C . {a.path} | less -R"
        elif what == "diagnosis":
            cmd = f"less .campaign/{qid}.diagnosis.md"
        elif what == "lessons":
            cmd = "less .campaign/lessons.md"
        else:
            cmd = f"awk '/^## {qid} /{{f=1}} f&&/^---$/{{exit}} f' docs/tasks.md | less"
        with self.suspend():
            subprocess.run(["bash", "-c", cmd], cwd=ROOT)

    def copy_last(self) -> None:
        a = self.current
        cmds = [s.text for s in (a.steps if a else []) if s.tool in ("Bash", "shell")]
        if not cmds:
            self.notify("агент ще не виконав жодної команди")
            return
        self.copy_to_clipboard(cmds[-1])
        self.notify(cmds[-1][:80], title="скопійовано")

    def toast_runs(self) -> None:
        """A toast for every attempt that ends while the TUI is open."""
        rows = runs()
        if self.runs_seen >= 0:
            for r in rows[self.runs_seen :]:
                good = r[10] in ("виконано", "хід майстра")
                self.notify(f"{r[1]} #{r[2]}: {r[10]} · {r[7]} · ${r[8]}", title="кидок завершено", severity="information" if good else "warning")
        self.runs_seen = len(rows)

    def fill_tabs(self, a: Attempt | None) -> None:
        steps = self.query_one("#steps-log", RichLog)
        key = (a.path if a else None, len(a.steps) if a else 0, "".join(s.mark + str(s.ok) for s in a.steps) if a else "")
        if key != self.steps_shown:
            self.steps_shown = key
            steps.clear()
            for i, s in enumerate(a.steps if a else [], 1):
                t = Text(f"#{i:<3} ", style="dim")
                t.append(f"{s.tool[:6]:<6} ", style="cyan")
                t.append(s.text[:110])
                if s.ok is not None:
                    t.append(" → ", style="dim")
                    t.append("ok" if s.ok else "✗", style="green" if s.ok else "red")
                    t.append(f" {s.lines}р", style="dim")
                if s.mark:
                    t.append("  " + s.mark, style="yellow")
                steps.write(t)
            for line in a.summary if a else []:
                steps.write(Text(line, style="dim"))
        words = self.query_one("#words-log", RichLog)
        wkey = (a.path if a else None, len(a.words) if a else 0)
        if wkey != self.words_shown:
            start = self.words_shown[1] if self.words_shown[0] == wkey[0] else 0
            if start == 0:
                words.clear()
            for kind, w in (a.words[start:] if a else []):
                style = {"💭": "dim italic", "✎": "bold", "▸": "cyan"}[kind]
                words.write(Text(f"{kind} {w}", style=style))
            self.words_shown = wkey
        if self.tick % 5 == 1:
            rl = self.query_one("#runs-log", RichLog)
            rl.clear()
            for r in reversed(runs()):
                icon, colour = TIERS.get(r[5], ("?", "white"))
                t = Text(f"{r[0][5:16]} ", style="dim")
                t.append(f"{r[1]:<6} #{r[2]:<2} {r[3]:<6} ")
                t.append(f"{icon} {r[5]:<6} ", style=colour)
                t.append(f"{r[7]:>4} ${r[8]:<5} rc={r[6]} ", style="dim")
                if r[9] not in ("0", "-"):
                    t.append(f"⛔{r[9]} ", style="yellow")
                t.append(r[10], style="green" if r[10] == "виконано" else "yellow" if r[10] == "хід майстра" else "red")
                rl.write(t)
            sl = self.query_one("#story-log", RichLog)
            sl.clear()
            cur = LOG_NAME.match(a.path.name)[1] if a else ""
            story = read(CAMPAIGN / f"{cur}.diagnosis.md")
            for line in story.splitlines() or ["діагнозу немає (буває лише після невдалої чи дорогої спроби)"]:
                sl.write(Text(line, style="bold cyan" if line.startswith("## ") else "yellow" if line.startswith("Урок:") else ""))
            lessons = read(CAMPAIGN / "lessons.md").splitlines()[-5:]
            if lessons:
                sl.write(Text("\nуроки для писаря", style="bold"))
                for line in lessons:
                    sl.write(line)


async def selftest() -> None:
    """Render once headless and check the pieces are there (checks.campaign-tui)."""
    app = CampaignTUI()
    async with app.run_test(size=(150, 50)) as pilot:
        await pilot.pause(0.5)
        diagram = str(app.query_one("#diagram", Static).render())
        side = str(app.query_one("#side", Static).render())
        for want in ("Наступний квест", "Агент", "Майстер", "4 quest-verify"):
            assert want in diagram, want
        assert "кроків" in side, side
        assert "сесія" in str(app.query_one("#quota", Static).render())
        await pilot.press("2", "4", "5", "1", "left_square_bracket", "0")
        await pilot.pause(0.2)
    print("campaign-tui: ok")


def main() -> None:
    if "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
        return
    if "--selftest" in sys.argv:
        asyncio.run(selftest())
        return
    if not sys.stdout.isatty():
        print("campaign-tui: needs a terminal", file=sys.stderr)
        sys.exit(2)
    CampaignTUI().run()


if __name__ == "__main__":
    main()
