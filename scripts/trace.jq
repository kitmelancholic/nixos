# scripts/trace: one line per tool call of an agent session, from the log
# scripts/agent writes (Claude Code stream-json or Codex exec --json, every
# line stamped with `_ts`). Run with `jq -rs --arg mode trace|notes`.
# Markers follow TraceProbe's detectors: a repeated call within 10 steps, a
# file read a third time within 10 steps, 10+ reads in a row with no write or
# command (a search loop), an output over 4k tokens, a call that ran over 5
# minutes, and over 5 minutes between a result and the next call.

def short($n): if length > $n then .[0:$n - 1] + "…" else . end;
def oneline: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
def pad($n): tostring | if length < $n then . + (" " * ($n - length)) else . end;
def lpad($n): tostring | if length < $n then (" " * ($n - length)) + . else . end;
def k: if . == null then "—" else (. / 100 | round / 10 | tostring) + "k" end;
def mins: . / 60 | round;
def text_of:
  if type == "string" then .
  elif type == "array" then map(if type == "object" then (.text // "") else tostring end) | join("\n")
  elif . == null then ""
  else tojson end;
def nlines: if . == "" then 0 else rtrimstr("\n") | split("\n") | length end;
# Rough tokens of a text: four characters each.
def tok: length / 4 | floor;
def rel: sub("^/.*?/nixos/"; "");
# `bash -lc '…'` (Codex) to the command itself.
def unwrap: sub("^(/usr/bin/env )?(ba)?sh -l?c "; "") | sub("^'(?<c>.*)'$"; "\(.c)") | sub("^\"(?<c>.*)\"$"; "\(.c)");
def readcmd: test("^(cat|head|tail|less|grep|rg|ls|find|fd|tree|wc|awk|jq|sed -n|git (show|log|diff|status|grep|ls-files|blame)|nix (eval|derivation show|path-info|search|flake (show|metadata))|scripts/opt)\\b");
# The file a read command looks at: its last word, if that looks like a path.
def cmdpath: (split(" ") | last) as $w | if ($w | test("[/.]")) and ($w | test("^-") | not) then ($w | rel) else null end;

def format:
  if any(.[]; .type == "thread.started" or ((.type // "") | startswith("item."))) then "codex"
  elif any(.[]; .type == "assistant" or .type == "result" or .subtype == "init") then "claude"
  else "unknown" end;

def main_assistant: .[] | select(.type == "assistant" and (.parent_tool_use_id // null) == null);

def claude_steps:
  ([.[] | select(.type == "user") | ._ts as $t | .message.content[]? | select(type == "object" and .type == "tool_result")
    | {key: .tool_use_id, value: (. + {_ts: $t})}] | from_entries) as $res
  | [main_assistant | . as $e
    | ($e.message.usage // {}) as $u
    | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $ctx
    | $e.message.content[]? | select(.type == "tool_use")
    | ($res[.id] // {}) as $r
    | ($r.content | text_of) as $out
    | .name as $tool
    | (.input // {}) as $in
    | (if $tool == "Bash" then ($in.command // "" | oneline)
       elif $in.file_path then ($in.file_path | rel)
       elif $in.pattern then $in.pattern
       else ($in | tojson) end) as $input
    | {ts: $e._ts, end: ($r._ts // $e._ts), ctx: $ctx, tool: $tool, input: $input,
       kind: (if ($tool | test("^(Read|Grep|Glob|LS|WebFetch|WebSearch)$")) then "read"
              elif ($tool | test("^(Edit|Write|MultiEdit|NotebookEdit)$")) then "write"
              elif $tool == "Bash" and ($input | readcmd) then "read"
              else "cmd" end),
       path: (if $in.file_path then ($in.file_path | rel) elif $tool == "Bash" and ($input | readcmd) then ($input | cmdpath) else null end),
       err: ($r.is_error // false), out_lines: ($out | nlines), out_tok: ($out | tok)}];

def codex_steps:
  ([.[] | select(.type == "item.started") | {key: .item.id, value: ._ts}] | from_entries) as $start
  | [.[] | select(.type == "item.completed") | . as $e | .item | .id as $id
    | select(.type | IN("command_execution", "file_change", "mcp_tool_call", "web_search"))
    | (if .type == "command_execution" then
         (.command | unwrap | oneline) as $c
         | {tool: "shell", input: $c, kind: (if $c | readcmd then "read" else "cmd" end),
            path: (if $c | readcmd then ($c | cmdpath) else null end),
            err: ((.exit_code // 0) != 0), out: (.aggregated_output // "")}
       elif .type == "file_change" then
         {tool: "patch", input: ([.changes[]?.path | rel] | join(", ")), kind: "write", path: null,
          err: (.status == "failed"), out: ""}
       elif .type == "mcp_tool_call" then
         {tool: "mcp:\(.server)/\(.tool)", input: (.arguments | tojson), kind: "read", path: null,
          err: (.status == "failed"), out: (.result | text_of)}
       else {tool: "web", input: (.query // ""), kind: "read", path: null, err: false, out: ""} end)
    | . + {ts: ($start[$id] // $e._ts), end: $e._ts, ctx: null, out_lines: (.out | nlines), out_tok: (.out | tok)} | del(.out)];

def steps: if format == "codex" then codex_steps else claude_steps end;

# Each step with its index (from 1), context growth and markers.
def annotate:
  . as $s
  | [range(0; length) as $i | $s[$i] as $x
    | [$s[[0, $i - 10] | max:$i][] | select(.tool == $x.tool and .input == $x.input)] as $same
    | (if $x.path != null and $x.kind == "read"
       then [$s[[0, $i - 9] | max:$i + 1][] | select(.kind == "read" and .path == $x.path)] | length
       else 0 end) as $reads
    | (if $i > 0 then $x.ts - $s[$i - 1].end else 0 end) as $gap
    | ($x.end - $x.ts) as $run
    | $x + {n: ($i + 1),
            delta: (if $i > 0 and $x.ctx != null and $s[$i - 1].ctx != null then $x.ctx - $s[$i - 1].ctx else null end),
            gap: $gap, run: $run,
            marks: ([
              (if ($same | length) > 0 and $reads < 2 then "⟳ повтор" else empty end),
              (if $reads >= 3 then "↺ \($reads)-тє читання" else empty end),
              (if $x.out_tok > 4000 then "▲ важкий вивід" else empty end),
              (if $gap > 300 then "⏸ \($gap | mins) хв без дій перед кроком" else empty end),
              (if $run > 300 then "⏱ виконувався \($run | mins) хв" else empty end)
            ])}];

# Runs of 10+ reads with no write or command between them.
def loops:
  reduce (.[], {kind: "end"}) as $x ({run: [], out: []};
    if $x.kind == "read" then .run += [$x.n]
    else (if (.run | length) >= 10 then .out += [{from: .run[0], to: .run[-1], len: (.run | length)}] else . end) | .run = [] end)
  | .out;

def line:
  "#\(.n | pad(3)) ctx \(.ctx | k | lpad(6)) \(if .delta == null then "        " else "(+\(.delta | k))" | pad(8) end)  \(.tool | pad(6)) \(.input | short(58) | pad(58)) → \(if .err then "✗" else "ok" end), \(.out_lines) рядк."
  + (if .out_tok >= 500 then " ~\(.out_tok | k)" else "" end)
  + (if (.marks | length) > 0 then "   " + (.marks | join(", ")) else "" end);

def summary($all):
  . as $s
  | ($all | map(select(.type == "result")) | last) as $result
  | ($all | map(select(.type == "turn.completed")) | last) as $turn
  | ($all | map(._ts // empty)) as $times
  | (if ($times | length) > 1 then ($times | max) - ($times | min) else 0 end) as $dur
  | [
      "підсумок: \($s | length) кроків (\([$s[] | select(.kind == "read")] | length) читань/пошуків, \([$s[] | select(.kind == "write")] | length) змін, \([$s[] | select(.kind == "cmd")] | length) команд), \($dur | mins) хв"
      + (if $result.total_cost_usd then ", $\($result.total_cost_usd * 100 | round / 100)" else "" end)
      + (if $turn.usage then ", токени: вхід \($turn.usage.input_tokens | k) (кеш \(($turn.usage.cached_input_tokens // 0) | k)), вихід \($turn.usage.output_tokens | k)" else "" end),
      (if any($s[]; .ctx != null) then "контекст: до \([$s[].ctx // 0] | max | k)" else empty end),
      ([$s[] | select(.out_tok >= 500)] | sort_by(-.out_tok) | .[0:3]
        | if length > 0 then "найважчі виводи: " + (map("#\(.n) ~\(.out_tok | k)") | join(", ")) else empty end),
      ([($s | loops[] | "цикл пошуку #\(.from)–#\(.to) (\(.len))"),
        ($s[] | select(any(.marks[]; startswith("⟳"))) | "повтор #\(.n)"),
        ($s[] | select(any(.marks[]; startswith("↺"))) | "повторне читання #\(.n) \(.path)")]
        | if length > 0 then "патерни: " + join("; ") else "патерни: немає" end),
      ($s | max_by(.run) // null | if . != null and .run > 60 then "найдовший крок: #\(.n), \(.run | mins) хв" else empty end),
      ($s | max_by(.gap) // null | if . != null and .gap > 60 then "найдовша пауза моделі: \(.gap | mins) хв перед #\(.n)" else empty end),
      (if $result then "відмови в дозволах: \($result.permission_denials // [] | length)"
        + ([$result.permission_denials[]? | .tool_input.command // .tool_input.file_path // .tool_name] | if length > 0 then " (" + (map(oneline | short(60)) | join("; ")) + ")" else "" end)
        else empty end),
      (if $result then "кінець: \($result.subtype // "?")\(if $result.is_error then ", помилка" else "" end)"
       elif $turn then "кінець: хід завершено"
       else "кінець: немає підсумку (сесію перервано?)" end)
    ][];

# The agent's own words, placed after the step they follow.
def notes:
  if format == "codex" then
    reduce (.[] | select(.type == "item.completed") | .item) as $it ({n: 0, out: []};
      if ($it.type | IN("command_execution", "file_change", "mcp_tool_call", "web_search")) then .n += 1
      elif $it.type == "agent_message" then .out += ["[після #\(.n)] текст: " + ($it.text | oneline | short(400))]
      elif $it.type == "reasoning" and (($it.text // "") != "") then .out += ["[після #\(.n)] думка: " + ($it.text | oneline | short(400))]
      else . end) | .out[]
  else
    reduce (main_assistant | .message.content[]?) as $c ({n: 0, out: []};
      if $c.type == "tool_use" then .n += 1
      elif $c.type == "text" and (($c.text // "") != "") then .out += ["[після #\(.n)] текст: " + ($c.text | oneline | short(400))]
      elif $c.type == "thinking" and (($c.thinking // "") != "") then .out += ["[після #\(.n)] думка: " + ($c.thinking | oneline | short(400))]
      else . end) | .out[]
  end;

if format == "unknown" then "trace: not a Claude Code or Codex log" | halt_error(1)
elif $mode == "notes" then notes
else
  . as $all
  | (steps | annotate) as $s
  | "\(format) · \($s | length) кроків", ($s[] | line), "…", ($s | summary($all))
end
