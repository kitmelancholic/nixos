# dangoNix quests

One section per quest, executed by the `quest` skill (`.agents/skills/quest/SKILL.md`:
`/quest` in Claude Code, `$quest` in Codex). Either agent can run or resume any
quest. Each section is self-contained: the agent reads only `AGENTS.md`, the end of
`docs/progress.md`, its own section and the files under *Read first*.
The GM-facing plan is `docs/remake.md`; the target design is `docs/design.md`.
This file links to the design and never restates it.

## Section format

```
## <id> — <quest name>
meta: tier=squire|hero|cleric effort=… boss=yes|no diff=<mode> [removed=<ids>] [leaves=<globs>] [rest=<tag>]
Goal           one sentence: the end state.
Why            enough context to resolve ambiguity in the steps.
Files          every path the quest may change ("the quest's paths"); docs/progress.md is always included.
Read first     files or design sections to read before editing.
Preconditions  facts to establish first; each says what to do with the outcome.
Steps          numbered, one action each; edits name the text to find, not a line number.
Do not         the traps for this quest.
Verify         commands beyond scripts/quest-verify, each with its expected output.
Stop if        the outcomes that end the run with `провалений кидок` (anything not covered also does).
AGENTS.md      what to change in it, or "no change".
Commit         the Conventional Commits subject (type, quest id as scope, `!` if breaking).
GM's turn      checklist for the GM with exact commands (omitted if none).
```

**`diff` modes** (enforced by `scripts/quest-verify <id>`):
- `baseline` / `source-only` — no oracle yet (before c1q03); only `scripts/check`.
- `none` — `scripts/closure-diff --assert-same HEAD` (compares derivation paths, evaluation only), plus `--removed` for each id in `removed=`.
- `leaves` — `scripts/closure-diff --names HEAD`: every changed leaf derivation must match a glob in `leaves=` (prefix `+` added, `-` removed, `~` changed); a glob ending in `?` is optional, every other glob must match at least once. Wrapper derivations (`home-manager-files`, `home-manager-path`, `home-manager-generation`, `etc`, `system-path`, `system-units`, `nixos-system-*`) are never listed.

**Commits** follow [Conventional Commits](https://www.conventionalcommits.org): `<type>(<quest id>)[!]: <subject>`, with the type and `!` given in each section's *Commit*. `!` marks a change the GM notices as a removal or an incompatible change; the body then has a `BREAKING CHANGE:` line saying what. Journal-only commits are `chore(<quest id>): <state>`; commits outside quests use a normal scope (`docs: …`, `fix(scripts): …`).

**Versions** follow [Semantic Versioning](https://semver.org) as git tags `vX.Y.Z`, set only at a long rest by `scripts/next-version` from the commits since the previous version: while `0.x`, a breaking change or `feat` bumps the minor, anything else the patch. `c1r3` releases `v1.0.0`.

**Checks.** `scripts/check --fast` while editing (doc and commit lint, shellcheck, flake evaluation without building); `scripts/check` is the full one (`nix flake check`), and `scripts/quest-verify` runs it. From c1q13 `dangonix check` is the same thing. CI on GitHub runs `scripts/check --fast` on every push and, once `scripts/closure-diff` exists, the oracle for every quest commit; the hero never pushes, so CI is the signal for the GM and the scribe.

**Models.** `tier=` names a row of the model table in `AGENTS.md` (`squire` for short mechanical quests with a strict oracle (`diff=none`, few steps, nothing to judge): c1q06, c1q07, c1q08, c1q09; `hero` by default; `cleric` for retries and for the quests whose code the rest depends on: c1q03, c1q13, c1q14; the judge behind `scripts/review` is `judge`), with a full model id per agent, so a campaign never changes model halfway. Claude Code's `scripts/context-watch` hook warns at 80k context tokens (stop exploring) and 95k (finish or hand the quest back with `провалений кидок`); the retry by the cleric keeps the uncommitted work. `scripts/campaign [--agent claude|codex] [--judge claude|codex]` picks the CLI; the journal records which agent and model ran each entry.

**Shared rules.**
- *Temporary worktree.* Tests that change `state.json`, `flake.lock` or Nix code on purpose run in a worktree inside the checkout (`.campaign/` is gitignored, and agents may edit only inside the checkout): `git stash create` prints a commit, or nothing on a clean tree; then `git worktree add --detach .campaign/wt-<id> <that commit or HEAD>`. Edit files under `.campaign/wt-<id>/` and evaluate `./.campaign/wt-<id>#…`. Finish with `git worktree remove --force .campaign/wt-<id>`; `git status` in the checkout must be unchanged afterwards.
- *Lock only drops.* After removing a flake input, `nix flake lock`, then `git show HEAD:flake.lock | jq --slurpfile new flake.lock '[$new[0].nodes[] | .locked.rev // empty] - [.nodes[] | .locked.rev // empty]'` must print `[]` (no revision appears that was not locked before; renumbered node names such as `nixpkgs_4` are fine).
- *Never touched by agents:* `hosts/nixos/hardware-configuration.nix`, `.claude/settings.json`, `.mcp.json`, `.codex/**`, `.git/**`, `scripts/hooks/**` (Claude Code or Codex's sandbox refuses them). A quest that needs one changed puts the exact change in the *GM's turn*.
- *Commands.* Run only what `.claude/settings.json` allows (headless runs deny the rest, and a denial the run cannot work around stops the campaign). Anything that activates, rebuilds, uses `sudo` or runs a `dangonix` `state`/`host` command without `--dry` belongs in the *GM's turn*.

**Writing a quest** (rules for the scribe, who maintains this file):
1. Check every fact against the branch the quest will run on: paths exist, quoted text is there, options and attribute names evaluate. A precondition that is already true or already false when the quest is written is a bug.
2. One action per step. Quote the text to replace and give the replacement; give each command with its expected output. Squire quests leave nothing to design.
3. *Files* lists every path the steps touch. A needed file missing from it stops the run (c1q02 lacked `home/desktop/wallpaper.nix`).
4. `leaves=`: a required glob only for a leaf that certainly changes in the union of the host and every theme's closure. A package that stays referenced elsewhere does not disappear (`hyprpolkitagent` stays in the theme homes when the host drops it). Build inputs of an added package (crates, `python3*-…`) and aggregates that follow any package change (`kit-fish-completions`, `man-paths`) are optional (`?`). `hm_…` leaves exist only for files written with `text =`, and their names have been guessed wrong before (c1q04, c1q05): make them optional and assert the file in *Verify* with `nix eval` instead.
5. Reading outside the checkout (e.g. a flake input's source in `/nix/store`) is refused in headless runs unless the GM allowed it; get paths with `nix eval --raw .#nixosConfigurations.nixos._module.specialArgs.inputs.<input>.outPath`.
6. Tests that need fixtures run as a Nix check (`pkgs.runCommand` with copies inside the build sandbox), not on files in `/tmp`.

---

## c1q00 — Roll call of heroes
meta: tier=hero effort=medium boss=no diff=baseline rest=c1r0

**Goal.** The uncommitted work that predates the remake is committed as the baseline, after the GM blesses it.

**Why.** Every later quest is measured against this commit, so a regression from the input update must surface here, not be blamed on a refactor.

**Read first.** `git status`, `git diff --stat`.

**Preconditions.** The working tree differs from `HEAD` in exactly: `flake.nix`, `flake.lock`, `home/packages.nix`, `patches/graphify-nix-support.patch`. Anything else → `провалений кидок` listing the extra paths.

**Steps.**
1. Without a `благословення` entry for c1q00 in the journal:
   - write the summary for the GM into the `хід майстра` entry: `flake.nix` (`pkgsUnstable` with `config.allowUnfree = true`); `home/packages.nix` (`pkgsUnstable.claude-code`); per changed `flake.lock` input, old → new revision and date, calling out `nixpkgs` and the held inputs `hyprland`, `noctalia`, `caelestia`; what changed in the graphify patch and whether the new `graphify` lock entry needs it;
   - run `nix flake check --no-write-lock-file` and build `.#nixosConfigurations.nixos.config.system.build.toplevel`;
   - commit only `docs/progress.md` and stop.
2. On `/quest retry c1q00` with `благословення`: `git add flake.nix flake.lock home/packages.nix patches/graphify-nix-support.patch`, commit, tag `redesign-baseline` and `c1r0`, append `виконано`.

**Do not.** Stage anything outside those five paths. Edit any Nix file.

**Verify.** ---

**AGENTS.md.** No change.

**Commit.** `chore(c1q00): baseline`

**GM's turn.**
- Read the summary.
- `just switch`, then `just home-switch`; use the desktop for a while.
- All good → append `## c1q00 — благословення`, run `/quest retry c1q00`.

---

## c1q01 — Reading the map
meta: tier=hero effort=medium boss=no diff=source-only

**Goal.** Confirm the docs and the pre-campaign tooling are in the branch and consistent, so later quests can rely on them.

**Why.** The docs and this file were committed on `main` before the remake and merged into `redesign`; a broken link or a missing section would mislead every later quest.

**Read first.** `docs/` listing, `README.md`.

**Steps.**
1. Check that `docs/vision.md`, `docs/design.md`, `docs/current-state.md`, `docs/remake.md`, `docs/tasks.md`, `AGENTS.md`, `CLAUDE.md` (only `@AGENTS.md`), `.agents/skills/quest/SKILL.md`, `.claude/skills/quest` (a symlink to it), `.claude/settings.json`, `.codex/config.toml`, `.codex/hooks.json`, `.codex/rules/dangonix.rules`, `.github/workflows/ci.yml`, `scripts/check`, `scripts/lint-docs`, `scripts/lint-commits`, `scripts/quest-verify`, `scripts/campaign`, `scripts/agent`, `scripts/review`, `scripts/hooks/` exist and `docs/redesign-plan.md`, `.claude/commands/` and `.claude/hooks/` do not.
2. `scripts/check --fast` passes (its `lint-docs` step checks links, quest headings, meta lines and commit subjects).
3. The git hooks installed in c1q00 (`commit-msg`, `reference-transaction`, `pre-push`) exist in `.git/hooks/` and match `scripts/hooks/`.
4. Anything wrong → `провалений кидок` naming it (do not fix docs yourself).

**Do not.** Edit any doc or Nix file.

**Verify.** Only the journal changes.

**AGENTS.md.** No change.

**Commit.** `chore(c1q01): map check`

---

## c1q02 — The mirror twin
meta: tier=hero effort=medium boss=no diff=source-only

**Goal.** The repo is no longer copied into the home closure, and `kit-profile` switches from the checkout.

**Why.** Today every commit (even a README typo) makes a new home generation, so "nothing changed" cannot be proven by out paths ([current-state](current-state.md)). The oracle in c1q03 needs this gone.

**Read first.** `flake.nix` (around line 139, `profileFlakeSource`), `lib/mk-home.nix` (lines 9, 34), `home/theme-switcher.nix`.

**Steps.**
1. Remove `profileFlakeSource` and every use of it.
2. Add the flake output `lib.themes` = the theme registry attrset.
3. `kit-profile` reads the flake **and** the theme list from the checkout: `$KIT_PROFILE_FLAKE`, else `~/nixos`, via `nix eval <flake>#lib.themes --json`. Remove the baked-in registry case tables. A missing checkout is a clear error. Keep the `KIT_THEME_FLAKE` fallback (removed in c1q18).

**Do not.** Change anything a theme builds besides `kit-profile` and the source path.

**Verify.**
- For every theme, `nix build .#checks.x86_64-linux.home-<id>` gives the same out path with a clean tree and with an uncommitted README edit.
- `nix path-info -r` of each activation package contains no copy of the repo.
- From `/tmp`: `kit-profile list` works; with `KIT_PROFILE_FLAKE` pointing at a copy, that copy is used.

**AGENTS.md.** No change.

**Commit.** `fix(c1q02): stop embedding the flake source`

**GM's turn.**
- `kit-profile switch noctalia`; the desktop comes back as before.
- All good → `## c1q02 — виконано`.

---

## c1q03 — Eye of the oracle ⚔️
meta: tier=cleric effort=high boss=yes diff=none

**Goal.** `scripts/closure-diff` proves "the system would not change" or names exactly what changes, by evaluation alone.

**Why.** Every later quest's expected diff is enforced by this script through `scripts/quest-verify`, and by CI on every pushed quest commit. Comparing derivation paths instead of out paths needs no build: equal `drvPath` means equal output, it runs without the Foundry ZIP, and it runs on GitHub's runners. It must survive the renames of c1q19.

**Read first.** `scripts/quest-verify` (its use of `--assert-same`, `--removed`, `--names`).

**Steps.** Write `scripts/closure-diff [--assert-same] [--added <id>…] [--removed <id>…] [--names] <rev>` comparing `<rev>` with the working tree:
1. Theme ids come from `lib.themes` at both revisions. Compare the `drvPath` of the host toplevel (`nixosConfigurations.nixos.config.system.build.toplevel`) and of `checks.x86_64-linux.home-<id>` for every id present at both, with `nix eval --raw`. Evaluate `<rev>` from a temporary worktree, never by checking it out in the checkout. Never rely on `homeConfigurations.kit-*` or option names.
2. `--assert-same` exits non-zero if any compared `drvPath` differs (print `nix-diff` of the two `.drv` files for each), if zero themes were compared, or if the added/removed themes are not exactly what `--added`/`--removed` declare.
3. `--names` compares the two derivation closures (`nix-store -qR <drv>`, `.drv` files only) and prints one changed leaf derivation per line as `<sign><name>`, where `<name>` is the `.drv` basename without hash and `.drv` (sign `+` only in the new closure, `-` only in the old, `~` same name on both sides whose own attributes differ once input store paths are masked, so a derivation that only rebuilds because an input changed is not listed; e.g. `+mcp-nixos-2.4.3`). Skip the wrapper derivations listed in this file's header. `scripts/quest-verify` matches these lines against the quest's `leaves=` globs.
4. Without flags it is a diagnostic: changed derivation names, `nix-diff` per differing top-level derivation, and the text diff of each theme's `hypr/hyprland.lua` (evaluated from `xdg.configFile`). `--build` additionally builds both sides and prints `nix store diff-closures`; it is the only mode that builds.
5. A bash script with `set -euo pipefail`; dependencies (`nix-diff`, `jq`) via `nix shell` or the devShell. It must pass `shellcheck` (`scripts/check` runs it): add it to the list in `scripts/check`.

**Do not.** Hard-code theme ids or option names.

**Verify.** `scripts/closure-diff --assert-same HEAD` passes on a clean tree without building any output (evaluation may still fetch sources: Hyprland's flake uses import-from-derivation). `scripts/quest-verify --oracle-only --base HEAD~1 c1q02` runs (the CI form). In a temporary worktree:
- (a) rename `kit.profile.id` to `dangonix.theme.id` throughout and move `profiles/` to `shells/` (`themes/` still holds classic palettes): `--assert-same` passes;
- (b) remove one theme: fails without `--removed <id>`, passes with it;
- (c) empty the registry: fails with "compared zero themes";
- (d) change one Hyprland option: fails and prints the `nix-diff`;
- (e) add a package to home: `--names` prints `+<name>`.

**AGENTS.md.** No change (c1q05 writes it).

**Commit.** `test(c1q03): output oracle`

---

## c1q04 — Banishing the graphomaniac
meta: tier=hero effort=medium boss=no diff=leaves leaves=-graphify-*,-graphify-codex-skill*,-graphifyy*,-networkx*,-numpy*,-rapidfuzz*,-tree*sitter*,-ncurses-abi5-compat*,-python3*?,~*?

**Goal.** Graphify is gone; Codex keeps its repo files (`.codex/`), and Zed's `codex-acp` stays.

**Why.** Graphify cost far more than it gave for 3.3k lines of Nix. Codex is a peer of Claude Code in the quest workflow ([design §12](design.md#12-агенти)); only the Graphify parts of its setup go.

**Read first.** `home/kit.nix` (line 15), `home/graphify.nix`, `home/pdf2md.nix` (line 32), `.gitignore`, `README.md` (around line 178).

**Steps.**
1. `git rm -r home/graphify.nix graphify-nix/ patches/graphify-nix-support.patch`; remove the import in `home/kit.nix`. HM then stops managing `~/.codex/AGENTS.md`, `~/.codex/hooks.json` and `~/.codex/skills/graphify`; c1q05 decides how Codex loads the repo's hooks.
2. Remove the `graphify` input from `flake.nix`; `nix flake lock` must only drop graphify nodes.
3. Remove the graphify `.gitignore` entries and the README line; fix the stale comment in `home/pdf2md.nix`.
4. Delete `graphify-out/` locally (untracked).

**Do not.** Remove `pyproject-nix`, `uv2nix`, `pyproject-build-systems` (pdf2md uses them), `.codex/`, `home/zed.nix`'s `codex-acp`, or anything in `~/.codex` besides what HM installed.

**Verify.** `rg -n -i graphify --glob '!docs/**'` finds nothing.

**AGENTS.md.** No change.

**Commit.** `refactor(c1q04)!: drop Graphify`

---

## c1q05 — Guild charter
meta: tier=hero effort=medium boss=no diff=leaves leaves=+mcp-nixos*,+bash-guard,+codex*,~claude-code*?,+*?,~*?

**Goal.** `AGENTS.md`, permissions for both CLIs, a fail-closed Bash guard, `mcp-nixos` and `scripts/opt` give Claude Code and Codex the same safe, short guidance.

**Why.** Lands right after c1q04 so old and new agent tooling never coexist. Either agent must be able to run or resume any quest with the same rules and guards. Design: [§12](design.md#12-агенти).

**Read first.** `AGENTS.md`, `.claude/settings.json`, `.claude/settings.local.json` (if present), `.codex/config.toml`, `.codex/hooks.json`, `.codex/rules/dangonix.rules`, `home/packages.nix`.

**Steps.**
1. `AGENTS.md` (English, ≤ 60 lines) describes only what exists now: what the repo is (two sentences, one machine); invariants (never edit `hardware-configuration.nix`; a theme never changes the host; every theme passes the checks; never remove or rebind an existing key); the loop `edit → nix fmt → scripts/check --fast → scripts/quest-verify <id>`; quests via `/quest` or `$quest` and the model table (keep it as is); stage files explicitly, never `git commit -a`; temporary worktrees for state-changing tests; the mcp-nixos line (look up names when unsure, 26.05 channel, it does not know flake-input options; for those use `scripts/opt`); one-line permission reminders; one line per top-level directory. `CLAUDE.md` stays the single line `@AGENTS.md`.
2. CLIs from nixpkgs-unstable without self-update: Claude Code — confirm the wrapper sets `DISABLE_AUTOUPDATER=1`, else wrap it; Codex — add `pkgsUnstable.codex` to home packages and turn its update check off (`check_for_update_on_startup = false` in `~/.codex/config.toml` via HM, if the key exists in that version). Note in the GM's turn any `~/.local/bin/claude`, `~/.npm-global` or other non-Nix `codex` install to remove.
3. `pkgs.mcp-nixos` in home packages; committed `.mcp.json` `{"mcpServers":{"nixos":{"command":"mcp-nixos"}}}` and `enabledMcpjsonServers: ["nixos"]` for Claude Code; `[mcp_servers.nixos] command = "mcp-nixos"` in `.codex/config.toml` for Codex.
4. Plugin `claude-md-management` only, via `extraKnownMarketplaces` (`claude-plugins-official`) and `enabledPlugins` in `.claude/settings.json`; marketplace auto-update off if the key exists. Codex gets no plugins.
5. Guard: a `writeShellApplication` `bash-guard` (deps in Nix, any internal error exits 2) that blocks any shell command whose text mentions `hardware-configuration.nix`, installed by HM at `~/.config/dangonix/hooks/bash-guard` (`xdg.configFile`, executable). Hook command `"$HOME/.config/dangonix/hooks/bash-guard" || exit 2` in both `.claude/settings.json` and `.codex/hooks.json`, next to `git-guard`. Claude Code: deny Edit/Write of `hosts/nixos/hardware-configuration.nix`, `.git/**`, `scripts/hooks/**`. Codex: if its hooks also see file edits (`apply_patch`), guard the same paths there; otherwise write in the GM's turn that Codex relies on its sandbox and the GM's review for them.
6. Permissions: `.claude/settings.json` was committed before c1q00 with the quest-loop allow list, the ask list, the deny rules and the `git-guard` hook, and `.codex/rules/dangonix.rules` mirrors its Bash rules (`allow`/`prompt`/`forbidden`); headless runs (`scripts/agent`) refuse anything not allowed, so keep every command the quest loop needs allowed in both (`nix flake lock` stays allowed: c1q07 and c1q09 need it). Add the step 3-5 keys, the `bash-guard` hook, and allow `foundry-status` and `scripts/opt *` in both files. Delete `.claude/settings.local.json` if present (its `git-guard` hook now lives in `settings.json`; it is already in `.gitignore`).
7. Codex loading: with the installed `codex`, establish whether it reads the project's `.codex/config.toml`, `.codex/hooks.json`, `.codex/rules/` and `.agents/skills/` (for example `codex exec --sandbox read-only 'list the skills and hooks you have'`, and the docs of that version). For each it does not, HM links the repo file into `~/.codex/` with `config.lib.file.mkOutOfStoreSymlink` (so edits in the checkout apply without a switch). Then confirm `codex exec --sandbox workspace-write` can run `scripts/check --fast` (nix-daemon socket, network); if not, fix it in `.codex/config.toml` (`writable_roots`, `network_access`) and say what in the GM's turn.
8. `scripts/opt [--home [<theme id>]] <option path>`: `nix eval` of the option in the real host configuration (or the theme's home configuration, default theme if no id), printing type, description, default and current value as JSON. Unlike mcp-nixos it knows options from flake inputs (Noctalia, Caelestia, Home Manager). Add it to the shellcheck list in `scripts/check`.

**Do not.** Add hookify or a formatting hook. Put the hook in a profile `bin` directory. Give one CLI a rule, guard or tool the other lacks without writing why in `AGENTS.md`.

**Verify.** `readlink -f "$(command -v claude)"` and `readlink -f "$(command -v codex)"` are in `/nix/store`; the Claude wrapper sets `DISABLE_AUTOUPDATER=1`. `scripts/opt --home noctalia programs.noctalia.enable` prints a description and `true`. Every Bash rule of `.claude/settings.json` has its counterpart in `.codex/rules/dangonix.rules`.

**AGENTS.md.** Written in this quest.

**Commit.** `feat(c1q05): AGENTS.md and agent tooling`

**GM's turn.**
- `just home-switch`; remove any non-Nix `claude` / `codex` copy the agent listed.
- In a new `claude` session: `claude mcp list` shows `nixos` connected; `/plugin` lists only `claude-md-management`; editing `hardware-configuration.nix` is refused; `cat hosts/nixos/hardware-configuration.nix` is blocked; `nix flake check` runs without a prompt; `sudo true` asks.
- In a new `codex` session in `~/nixos` (trust the project when asked): `/mcp` shows `nixos`; `$quest` is offered; `cat hosts/nixos/hardware-configuration.nix` is blocked; `git push` is refused; `nix flake check` runs without a prompt; `sudo true` asks.
- Negative: rename `~/.config/dangonix/hooks/bash-guard` away → every Bash command is blocked; `just home-switch` restores it.
- All good → `## c1q05 — виконано`.

---

## c1q06 — Under one banner
meta: tier=squire effort=medium boss=no diff=none

**Goal.** The registry default (what `.#kit` and a fresh install build) is `noctalia`, and the classic-only override canary is gone.

**Why.** Noctalia is the stable theme ([vision](vision.md)). The canary asserts Waybar values that only the classic themes have, so it would break when they go in c1q08. The default does not affect `checks.home-<id>` or the host, so nothing compared by the oracle changes.

**Files.** `profiles/default.nix`, `flake.nix`, `README.md`, `AGENTS.md`, `docs/progress.md`.

**Read first.** `profiles/default.nix`; in `flake.nix` the bindings `themeOverrideCanary`, `themeOverrideCheck`, `profileCheck` and the `checks` attrset.

**Preconditions.**
1. `git tag -l last-multi-theme`: prints nothing → `git tag last-multi-theme HEAD`; prints `last-multi-theme` → a previous run made it, keep it.

**Steps.**
1. `profiles/default.nix`: `default = "catppuccin";` → `default = "noctalia";`.
2. `flake.nix`: delete the whole binding that starts `themeOverrideCanary = profileHomes.${defaultProfile}.extendModules {` and ends with the `};` just before `themeOverrideCheck =`.
3. `flake.nix`: delete the whole binding that starts `themeOverrideCheck =` and ends with `pkgs.runCommand "theme-override-check" { } "touch $out";`.
4. `flake.nix`, in `profileCheck`: `(builtins.attrValues homeChecks) ++ (builtins.attrValues hyprlandChecks) ++ [ themeOverrideCheck ];` → `(builtins.attrValues homeChecks) ++ (builtins.attrValues hyprlandChecks);`.
5. `flake.nix`, in `checks.${settings.system}`: delete the line `theme-override = themeOverrideCheck;`.
6. `README.md`: `` `catppuccin` (default), `` → `` `catppuccin`, ``; `` `noctalia`, and `caelestia`. `` (the line after it) → `` `noctalia` (default), and `caelestia`. ``; `reports the default `catppuccin`` → `reports the default `noctalia``; `(default Catppuccin)` → `(default Noctalia)`.
7. `AGENTS.md`: `theme registry (default `catppuccin`)` → `theme registry (default `noctalia`)`.
8. `nix fmt`, then `scripts/check --fast`.

**Do not.** Touch any theme module, `lib/`, or any other check.

**Verify.**
- `rg -n themeOverride --glob '!docs/**'` prints nothing.
- `nix eval --raw .#homeConfigurations.kit.config.kit.profile.id` prints `noctalia`.
- `nix eval .#checks.x86_64-linux --apply builtins.attrNames` does not contain `"theme-override"`.

**Stop if.** `scripts/quest-verify c1q06` reports a changed `drvPath`: write the first 20 lines of its `nix-diff` into the entry.

**AGENTS.md.** Step 7.

**Commit.** `feat(c1q06)!: default theme noctalia`
(body: `BREAKING CHANGE: .#kit and a fresh install now build noctalia instead of catppuccin.`)

---

## c1q07 — Fall of the Dark Master
meta: tier=squire effort=medium boss=no diff=none removed=dms

**Goal.** The `dms` theme (Dank Material Shell) no longer exists in the repo.

**Why.** Only Noctalia and Caelestia stay ([design §3](design.md#3-теми)); every extra theme is an external input that churns.

**Files.** `profiles/dms/` (deleted), `profiles/default.nix`, `flake.nix`, `flake.lock`, `README.md`, `docs/progress.md`.

**Read first.** `profiles/default.nix`; in `flake.nix` the `inputs`, `selectorArchitectureCheck` and `profileOwnershipCheck`.

**Preconditions.**
1. `git tag -l last-multi-theme` prints `last-multi-theme`. Prints nothing → stop.

**Steps.**
1. `git rm -r profiles/dms`.
2. `profiles/default.nix`: delete the block `dms = { … };` (its four lines `name = "DankMaterialShell";`, `description = …;`, `module = ./dms;` and the braces).
3. `flake.nix`, in `inputs`: delete the line `dms.url = "github:AvengeMedia/DankMaterialShell/stable";`.
4. `flake.nix`, in `selectorArchitectureCheck`: delete the list item `"dms.service"`.
5. `flake.nix`, in `profileOwnershipCheck`: delete the four lines that start `assert profileHomes.dms.` or `assert !profileHomes.dms.`.
6. `README.md`: delete every `` `dms`, `` (two places) and the line `home-manager switch --flake .#kit-dms`.
7. `nix flake lock`, then the *Lock only drops* check from the shared rules: it prints `[]`.
8. `nix fmt`, then `scripts/check --fast`.

**Do not.** Touch other themes or inputs. Run `nix flake update`.

**Verify.**
- `rg -n -i 'dms|dank' --glob '!docs/**'` prints nothing.
- `nix eval .#lib.themes --apply 'r: builtins.attrNames r.profiles'` does not contain `"dms"`.

**Stop if.** The lock check prints anything but `[]`; `scripts/quest-verify c1q07` reports a changed `drvPath` for a theme that stays.

**AGENTS.md.** No change.

**Commit.** `refactor(c1q07)!: retire DMS`
(body: `BREAKING CHANGE: the dms theme is gone; kit-profile switch dms fails.`)

---

## c1q08 — Twilight of the classics
meta: tier=squire effort=medium boss=no diff=none removed=catppuccin,tokyo-night,gruvbox,kit-dark

**Goal.** The classic family is gone; only Noctalia and Caelestia remain.

**Why.** Retired by decision; `nix flake check` drops from 7 + 7 builds to 2 + 2. Every file below is used only by `profiles/classic/` or the four classic themes, so the two shells must stay byte-identical.

**Files.** `themes/`, `profiles/classic/`, `home/waybar.nix`, `home/osd.nix`, `home/power.nix`, `home/screenshots.nix`, `home/desktop/theme.nix`, `home/desktop/wallpaper.nix`, `home/hyprland/settings.nix`, `home/hyprland/binds.nix`, `assets/` (all deleted), `profiles/default.nix`, `home/options.nix`, `flake.nix`, `README.md`, `AGENTS.md`, `docs/progress.md`.

**Read first.** `profiles/default.nix`, `profiles/classic/default.nix`, `home/options.nix` (`launcher.command`); in `flake.nix` `selectorArchitectureCheck` and `profileOwnershipCheck`.

**Steps.**
1. `git rm -r themes profiles/classic home/waybar.nix home/osd.nix home/power.nix home/screenshots.nix home/desktop/theme.nix home/desktop/wallpaper.nix home/hyprland/settings.nix home/hyprland/binds.nix assets`.
2. `profiles/default.nix`: delete the four blocks `catppuccin = { … };`, `tokyo-night = { … };`, `gruvbox = { … };`, `kit-dark = { … };`. Only `noctalia` and `caelestia` remain under `profiles`.
3. `home/options.nix`: delete the option `launcher.command = lib.mkOption { … };` (five lines, `default = "wofi --show drun";`).
4. `flake.nix`, in `selectorArchitectureCheck`: delete the line `assert !(lib.hasInfix "hyprland.start" (builtins.readFile ./home/hyprland/settings.nix));`. Keep the rest of that check (c1q11 replaces it).
5. `flake.nix`, in `profileOwnershipCheck`: delete `assert profileHomes.catppuccin.config.programs.waybar.enable;` and `assert profileHomes.catppuccin.config.services.dunst.enable;`.
6. `rg -n 'themes/|profiles/classic|waybar\.nix|osd\.nix|power\.nix|screenshots\.nix|desktop/theme\.nix|wallpaper\.nix|hyprland/settings\.nix|hyprland/binds\.nix|kit\.apps\.launcher|kit\.classic|catppuccin|tokyo-night|gruvbox|kit-dark' --glob '!docs/**' --glob '!README.md' --glob '!AGENTS.md'` prints nothing. A hit is a leftover reference: remove it if it is in a file listed in *Files*, otherwise stop.
7. `README.md`:
   - `` - `profiles/`: the explicit profile registry, classic family, and external-shell adapters. `` → `` - `profiles/`: the theme registry and the shell adapters (Noctalia, Caelestia). ``;
   - delete the line `` - `themes/`: the four classic palette variants. ``;
   - the two lines that list the registry (`` `catppuccin`, `tokyo-night`, …`` and `` `noctalia` (default), and `caelestia`. ``) → `` `noctalia` (default) and `caelestia`. ``;
   - delete the two lines that start `The four classic palettes share one profile family` and end `screenshots, and classic binds.`;
   - `kit-profile switch gruvbox` → `kit-profile switch caelestia`;
   - the line `The available IDs are …` and the next one → `` The available IDs are `noctalia` and `caelestia`. ``;
   - delete the lines `home-manager switch --flake .#kit-catppuccin`, `.#kit-tokyo-night`, `.#kit-gruvbox`, `.#kit-dark`.
8. `AGENTS.md`: delete the line `` - `themes/` colour variants of the classic desktop. ``; `` - `assets/` wallpapers. `docs/` vision, design, plan, journal. `` → `` - `docs/` vision, design, plan, journal. ``.
9. `nix fmt`, then `scripts/check --fast`.

**Do not.** Remove the Stylix import or input (c1q09). Touch `profiles/noctalia`, `profiles/caelestia`, `profiles/common` or `home/hyprland/lua-helpers.nix`.

**Verify.** `nix eval .#lib.themes --apply 'r: builtins.attrNames r.profiles'` prints `[ "caelestia" "noctalia" ]`.

**Stop if.** `scripts/quest-verify c1q08` reports a changed `drvPath` for noctalia, caelestia or the host: the classic code leaked into them; write the first 20 lines of the `nix-diff` into the entry.

**AGENTS.md.** Step 8.

**Commit.** `refactor(c1q08)!: retire the classic family`
(body: `BREAKING CHANGE: catppuccin, tokyo-night, gruvbox and kit-dark are gone with Waybar, Dunst, SwayOSD and the classic binds.`)

---

## c1q09 — Dispelling Stylix
meta: tier=squire effort=medium boss=no diff=none

**Goal.** Stylix is gone.

**Why.** Only the retired themes used it; the contract has no `stylix` value ([design §3](design.md#ролі-контракт)). With no theme setting `stylix.*`, its module is imported but disabled, so removing it must change nothing built.

**Files.** `lib/mk-home.nix`, `flake.nix`, `flake.lock`, `home/desktop/cursor.nix`, `docs/progress.md`.

**Read first.** `lib/mk-home.nix`, `home/desktop/cursor.nix`; the `stylix` block in `flake.nix` `inputs`.

**Steps.**
1. `lib/mk-home.nix`: delete the line `inputs.stylix.homeModules.stylix`.
2. `flake.nix`, in `inputs`: delete the block `stylix = { url = "github:nix-community/stylix/release-26.05"; inputs = { nixpkgs.follows = "nixpkgs"; }; };` (six lines).
3. `home/desktop/cursor.nix`: the two comment lines `# One cursor for every theme: …` and `# classic themes' Stylix sets the same cursor and wins until c1q09.` → the one line `# One cursor for every theme: GTK apps (Nautilus), X11 and Hyprland.`. Change no code.
4. `nix flake lock`, then the *Lock only drops* check: it prints `[]`.
5. `nix fmt`, then `scripts/check --fast`.

**Do not.** Paper over a diff by setting options.

**Verify.** `rg -n -i stylix --glob '!docs/**'` prints nothing.

**Stop if.** `scripts/quest-verify c1q09` reports a changed `drvPath`: something disabled Stylix still set; write the first 20 lines of the `nix-diff` into the entry.

**AGENTS.md.** No change.

**Commit.** `refactor(c1q09): drop Stylix`

---

## c1q10 — Cleaning the castle ⚔️
meta: tier=hero effort=medium boss=yes diff=leaves leaves=-blueman*,-network-manager-applet*,-hyprpolkitagent*?,-hyprlock*?,-*?,~dbus*?,~unit-*?,~*pam*?,~man-paths?,~source?,~system-generators?,~system-shutdown?,~system_fish-completions?,~user-generators?,~user-units? rest=c1r1

**Goal.** The host keeps only what the remaining lock screens need, and the tray no longer duplicates the shells' own Wi-Fi and Bluetooth.

**Why.** After c1q08 nothing uses the classic lock stack. `services.blueman` and `networkmanagerapplet` are leftovers too: their XDG autostart entries (UWSM runs them) put blueman-applet and nm-applet in the tray next to the Wi-Fi and Bluetooth panels Noctalia and Caelestia already have, so the GM sees each twice. `bluetuith` stays as the terminal fallback. Host changes need the GM's switch, so this is act I's boss. Both themes keep their own `hyprpolkitagent` user unit (`profiles/common/hyprpolkitagent.nix`), so that package stays in the closure.

**Files.** `hosts/nixos/desktop.nix`, `docs/progress.md`.

**Read first.** `hosts/nixos/desktop.nix`.

**Preconditions.** Find the PAM service the Noctalia **and** the Caelestia lock screens authenticate with:
1. `nix eval --raw .#nixosConfigurations.nixos._module.specialArgs.inputs.noctalia.outPath` and the same for `caelestia` print two store paths.
2. `rg -n -i 'pam|hyprlock' <path>` in each. Look for a PAM config name (a string passed to a PAM context or `pam_start`, e.g. `"login"`, `"hyprlock"`, `"passwd"`).
3. Either uses `hyprlock` → keep `programs.hyprlock` and the `hypridle` force-disable; neither → drop both. Cannot tell, or reading the store path is refused → stop with what you found.

**Steps.**
1. In `environment.systemPackages`: delete `hyprpolkitagent # Wayland polkit authentication agent` and `networkmanagerapplet # NetworkManager tray integration`.
2. In `services`: delete `blueman.enable = true;`.
3. Only if the precondition said drop: delete `hyprlock.enable = true;` from `programs`, and from `services` the three comment lines starting `# programs.hyprlock force-enables` plus `hypridle.enable = lib.mkForce false;`. If `lib` is then unused in the file's argument set, remove it (deadnix fails otherwise).
4. `nix fmt`, then `scripts/check --fast`.

**Do not.** Remove only one of the hyprlock / hypridle pair. Touch other PAM services. Disable `hardware.bluetooth` or NetworkManager.

**Verify.**
- `nix build --no-link .#nixosConfigurations.nixos.config.system.build.toplevel` succeeds.
- `nix eval .#nixosConfigurations.nixos.config.hardware.bluetooth.enable` and `… .config.networking.networkmanager.enable` print `true`.
- `scripts/closure-diff HEAD` shows no change for `home-noctalia` or `home-caelestia`.

**AGENTS.md.** No change.

**Commit.** `refactor(c1q10)!: host cleanup after classic`
(body: `BREAKING CHANGE: blueman and nm-applet tray applets removed; use the shell's Wi-Fi and Bluetooth panels or bluetuith.`)

**GM's turn.**
- `just switch` (sudo).
- In Noctalia and Caelestia: lock, unlock with password, unlock with fingerprint (only if `fprintd-list kit` shows an enrolled finger), suspend and resume; the tray shows no blueman or nm-applet icon, and the shell's own Wi-Fi and Bluetooth panels still connect.
- Long rest: read the reviewer's findings, push `redesign`, merge the PR into `main` as a merge commit, `git switch main && git pull --ff-only && git switch redesign`.
- All good → `## c1q10 — виконано`.

---

## c1q11 — Warding runes ⚔️
meta: tier=hero effort=high boss=yes diff=none

**Goal.** All checks live in `lib/checks.nix`, generic over the registry, plus a host build check and a frozen bind fixture.

**Why.** Today some checks grep source files or hard-code theme names, and none builds the host, so a host-only error passes ([current-state](current-state.md)). Design: [§3 checks](design.md#перевірки-static-libchecksnix-на-кожну-тему), [binds as data](design.md#бінди--це-дані).

**Files.** `lib/checks.nix` (new), `flake.nix`, `lib/repo-apps.nix`, `profiles/noctalia/default.nix`, `profiles/caelestia/default.nix`, `home/hyprland/lua-helpers.nix`, `tests/binds/` (new), `AGENTS.md`, `docs/progress.md`.

**Read first.** `flake.nix` (every binding used by `checks`), `profiles/noctalia/binds.nix`, `home/hyprland/lua-helpers.nix`, `lib/repo-apps.nix` (`themeCheckScript`, `hyprlandCheckScript`).

**Steps.**
1. Add `lib/checks.nix` (a function of what it needs: `pkgs`, `lib`, the registry, the homes, the host); `flake.nix` only wires its result into `checks.${settings.system}`.
2. Delete the grep checks (`selectorArchitectureCheck`), hard-coded assertions (`profileOwnershipCheck`) and the alias checks `profile`, `profile-selector`, `profile-ownership`, `theme`, `hyprland`, `home`.
3. Check `registry` (design check 1): unique ids, the registry entry's module path exists, valid manifest fields (`name`, `description`, `module`), `kit.profile.id == id`. Family invariants become assertions in the family module: Noctalia asserts `programs.noctalia.enable`, `systemd.enable` and `settings.shell.launch_apps_as_systemd_services`; Caelestia asserts `programs.caelestia.enable`, `systemd.enable`, `cli.enable`.
4. Check `host`: builds the host toplevel.
5. Bind key resolver in Nix (normalise `mod` → `SUPER`, modifier order SUPER CTRL ALT SHIFT, separator ` + `) and frozen fixture `tests/binds/<id>.json` per theme with binds (Caelestia has none: an empty list): each entry is the full resolved bind (key, action, arguments, every flag, e.g. `{ mouse = true; }`); check `binds-fixture` compares the evaluated binds with the fixture.
6. `lib/repo-apps.nix`: `themeCheckScript` builds `.#checks.<system>.registry`; `hyprlandCheckScript` builds every `hyprland-<id>` check (they referenced the deleted aliases).

**Do not.** Change any built output. Leave a check that greps source text.

**Verify.** `nix eval .#checks.x86_64-linux --apply builtins.attrNames` prints exactly `static`, `registry`, `binds-fixture`, `host`, `home-<id>`, `hyprland-<id>` for both ids. Negative tests in the temporary worktree (shared rules), each with `nix build --no-link ./.campaign/wt-c1q11#checks.x86_64-linux.<check>` failing, restoring the file after each:
- change one fixture action → `binds-fixture` fails;
- drop `mouse = true` from one mouse bind in the fixture → fails;
- duplicate a registry id (copy `noctalia` as a second key with the same module and `kit.profile.id`) → `registry` fails;
- set `boot.kernelPackages = pkgs.linuxPackages_does_not_exist;` in `hosts/nixos/configuration.nix` → `host` fails.

**AGENTS.md.** One line: checks live in `lib/checks.nix`; the bind fixture changes only with a declared behavior change.

**Commit.** `test(c1q11): checks out of flake.nix`

---

## c1q12 — Book of choices
meta: tier=hero effort=medium boss=no diff=none

**Goal.** A tracked `state.json` holds every choice a command can make: the theme and the Foundry instances.

**Why.** [Design §4](design.md#4-statejson). Foundry uses the instances shape from the start, but with one instance `main` that maps to today's single service and data, so nothing built changes; several instances arrive in campaign II ([design §9](design.md#9-foundry-vtt)).

**Files.** `state.json` (new), `flake.nix`, `lib/settings.nix`, `lib/checks.nix`, `lib/repo-apps.nix`, `hosts/nixos/foundryvtt.nix`, `home/foundry.nix`, `profiles/default.nix`, `AGENTS.md`, `docs/progress.md`.

**Read first.** `lib/settings.nix`, `hosts/nixos/foundryvtt.nix`, `home/foundry.nix`, `lib/repo-apps.nix` (`foundryCheckScript`), `profiles/default.nix`.

**Preconditions.** `nix eval --raw .#nixosConfigurations.nixos._module.specialArgs.inputs.foundryvtt.outPath` gives the nix-foundryvtt source; find its version table (`rg -n '14\.361|sha256' <path>`) and confirm it carries, per version, the payload filename and hash its package uses. Not so, or reading the path is refused → stop.

**Steps.**
1. Add `state.json`: `{ "theme": "noctalia", "foundry": { "instances": { "main": { "version": "14.0.0+361", "port": 30000 } } } }` and nothing else (the values are today's `settings.foundry.version` and `port`); `git add state.json`.
2. `flake.nix` reads it once (`state = lib.importJSON ./state.json;`). `homeConfigurations.kit` builds `state.theme`; delete `default` from `profiles/default.nix`. The flake output `lib.themes` stays the registry plus `default = state.theme;`, so `kit-profile` keeps working until c1q18.
3. The host gets only `state.foundry` (via `specialArgs`), never `state.theme`. `lib/settings.nix` derives `foundry.version` and `foundry.port` from `state.foundry.instances.main` and keeps `service` and `url`; an assertion fails evaluation with "several Foundry instances arrive in campaign II" if there is more than one instance, and empty `instances` disables Foundry (`services.foundryvtt.enable = false`, no firewall port, no sudo rules).
4. Delete `shortVersion`, `filename`, `hash` from `lib/settings.nix`; `foundryCheckScript` derives filename and hash from the nix-foundryvtt table.
5. Check `registry` gains "`state.json`'s theme exists in the registry".

**Do not.** Change the Foundry unit name, data dir or port.

**Verify.** `nix run .#foundry-check` prints `foundry ok: 14.0.0+361`. In the temporary worktree, a `version` absent from the table makes `nix eval ./.campaign/wt-c1q12#nixosConfigurations.nixos.config.system.build.toplevel.drvPath` fail with a message naming the version; a `theme` absent from the registry fails `registry`.

**AGENTS.md.** "`state.json` holds the GM's choices; change it only when asked."

**Commit.** `refactor(c1q12): state file`

---

## c1q13 — Forging dangonix ⚔️
meta: tier=cleric effort=high boss=yes diff=leaves leaves=+dangonix*,+hm_*dangonix*?,~kit-fish-completions?,~man-paths?

**Goal.** `dangonix` v1 exists next to the old commands: every subcommand, the grammar, `--json` and `--dry`; the read commands and `check` work for real, and every `state`/`host` command so far only plans (`--dry`).

**Why.** The single CLI is the heart of the design: [§5](design.md#5-dangonix), [transactions](design.md#транзакції), [§6](design.md#6-стабільність). This is the first of three quests (c1q14 transactions, c1q15 VM tests); later campaigns extend this code, so its structure matters more than in any other quest.

**Files.** `lib/dangonix/` (new), `home/dangonix.nix` (new), `home/kit.nix`, `home/options.nix`, `flake.nix`, `scripts/check`, `AGENTS.md`, `docs/progress.md`.

**Read first.** Design §5 in full; `home/theme-switcher.nix`, `lib/settings.nix`, `scripts/check`.

**Steps.**
1. `lib/dangonix/` (`default.nix`, `commands.nix` with `effect`, `agent` and `wraps` (the raw commands a row wraps, [design §11 agents](design.md#агенти); only data until campaign II), `dangonix.sh`) and `home/dangonix.nix`; `apps.default = dangonix`; option `kit.repo` (default `~/nixos`, renamed in c1q19).
2. Subcommands: `switch`, `check [--fast|--vm]` (absorbs `scripts/check`: the same steps and modes, plus `host`; `scripts/check` becomes `exec nix run "$(git rev-parse --show-toplevel)" -- check "$@"` so CI and `quest-verify` keep working), `update` (held list, reports held), `theme`, `commands`, `status`, `help`, `version`, `history` (reads the transaction journal), and `foundry` limited to one instance: `list`, `status|logs|start|stop|restart|open [main]`, where `status` and `foundry status` show only what exists by now (power, net, shield, Funnel and backup arrive with their features in campaign II and III), `import <zip>`, `upgrade main <zip>`, `add main <zip>`, `remove main`. Every command has `--json`. `--dry` is accepted by every command: a non-`read` command only plans, a `read` command runs as usual. Grammar, global flags (`--yes`, `--metered-ok` included), the JSON envelope and exit codes follow [design §5 grammar](design.md#граматика).
3. In this quest every `state`/`host` command only plans: without `--dry` it refuses with exit 4 ("not available before c1q14") and changes nothing; `check --vm` refuses the same way until c1q15.
4. Fish completions for `dangonix` generated from the command table.

**Do not.** Remove or change any old command. Implement any `state`/`host` effect (that is c1q14). Edit `.claude/settings.json` or `.codex/rules/` (the GM already allowed `nix run . -- --dry …`, `nix run . -- check …`, `dangonix --dry …` and `dangonix check …`).

**Verify.** Run the CLI as `nix run . -- <args>`, global flags first.
- `nix run . -- check --fast` gives the same result as `scripts/check --fast` did before step 2.
- `nix run . -- --dry --json theme` marks noctalia.
- `nix run . -- --dry --json commands | jq -r '.data[].name'` lists every command; each runs as `nix run . -- --dry --json <name> …` without a prompt and its output passes `jq -e .`.
- `nix eval .#homeConfigurations.kit.config.xdg.configFile --apply 'f: builtins.hasAttr "fish/completions/dangonix.fish" f'` prints `true` (or the same for `home.file`, wherever step 4 put it).

**AGENTS.md.** Loop becomes `edit → nix fmt → dangonix check --fast → dangonix check → scripts/closure-diff`; discovery `dangonix --dry --json commands`.

**Commit.** `feat(c1q13): dangonix v1 commands`

**GM's turn.**
- `just home-switch`; `dangonix status`, `dangonix help`, `dangonix --dry switch` look right to you.
- All good → `## c1q13 — виконано`.

---

## c1q14 — Tempering the blade ⚔️
meta: tier=cleric effort=high boss=yes diff=leaves leaves=~dangonix*,~hm_*dangonix*?

**Goal.** Every `state`/`host` command of `dangonix` runs as a transaction, and the agents' permission rules for `dangonix` are fixed by its grammar.

**Why.** The single CLI is the heart of the design: [§5](design.md#5-dangonix), [transactions](design.md#транзакції), [§6](design.md#6-стабільність). Permissions do not follow each new command: `--dry` is a no-op for `read` commands, so allowing `dangonix --dry …` and `dangonix check …` covers everything an agent may run, and every other `dangonix` call is unmatched, so Claude Code asks (headless: refuses) and Codex's sandbox blocks the activation ([design: effect і agent](design.md#effect-і-agent)). A catch-all `ask` rule would be wrong: ask beats allow in both CLIs.

**Files.** `lib/dangonix/`, `home/dangonix.nix`, `lib/checks.nix`, `AGENTS.md`, `docs/progress.md`.

**Read first.** Design §5 (transactions) and §6 in full; `lib/dangonix/`; `home/theme-switcher.nix` (lock, activation).

**Steps.**
1. Every `state`/`host` command is the transaction from design §5: one lock (reuse `kit-home-activation.lock`) around snapshot, preflight, `state.json` edit, build, nvd diff, host activation, home activation, recovery, and the journal line in `~/.local/state/dangonix/journal.jsonl`.
2. Design check 7 in `lib/checks.nix` as check `commands`: every row of the command table has `effect` and `agent`; `agent = "allow"` only for `read` rows (and `check`); every non-`read` row implements `--dry`; the only rules in `.claude/settings.json` that start with `dangonix` are the allow rules `Bash(dangonix --dry *)`, `Bash(dangonix check)`, `Bash(dangonix check *)`, and `.codex/rules/dangonix.rules` has their counterparts and no other `dangonix` rule (the GM added them before c1q13; the check only reads the files).

**Do not.** Remove or change any old command. Test failures in the checkout. Edit `.claude/settings.json` or `.codex/rules/`.

**Verify (checkout).** `nix run . -- --dry switch` reports no change; `nix run . -- --dry --json theme caelestia` names the steps it would run and leaves `git diff` empty. In the worktree, add `"Bash(dangonix theme *)"` to the allow list of `.campaign/wt-c1q14/.claude/settings.json` → `nix build --no-link ./.campaign/wt-c1q14#checks.x86_64-linux.commands` fails.

**Verify (temporary worktree `.campaign/wt-c1q14`, `nix run . -- --flake ./.campaign/wt-c1q14 …`; nothing here activates).**
1. `update`: held inputs byte-identical in the worktree's `flake.lock`, JSON `held` lists them; `update hyprland` changes only `hyprland`; with a broken check, `update` exits non-zero and `git diff --no-index --exit-code flake.lock .campaign/wt-c1q14/flake.lock` prints nothing.
2. Foundry preflight: a version in the table but not in the store → `failedStep: "preflight"` naming `dangonix foundry import <zip>`; a ZIP with one changed byte or an unsupported version is rejected with the worktree's `state.json` unchanged and no GC root.

**AGENTS.md.** One line: agents run `dangonix --dry …` and `dangonix check …`; every real `dangonix` change asks.

**Commit.** `feat(c1q14): dangonix transactions`

**GM's turn.**
- `dangonix switch` (sudo); `dangonix theme caelestia` and `dangonix theme noctalia`; after both `git -C ~/nixos diff state.json` is empty.
- `sudo -u nobody dangonix switch` refuses.
- Foundry round-trip: `dangonix foundry remove main`, then `dangonix foundry add main <zip>`; `git -C ~/nixos diff state.json` is empty afterwards.
- All good → `## c1q14 — виконано`.

---

## c1q15 — Trial by fire
meta: tier=hero effort=high boss=no diff=leaves leaves=~dangonix*? rest=c1r2

**Goal.** The transaction cases that break activation on purpose are tested in a VM by `dangonix check --vm`.

**Why.** Recovery after a failed host or home activation cannot be tested on the laptop without risk ([design §5 transactions](design.md#транзакції)).

**Files.** `tests/dangonix-vm/` (new), `flake.nix`, `lib/dangonix/`, `AGENTS.md`, `docs/progress.md`.

**Read first.** Design §5 (transactions); `lib/dangonix/` (the transaction code from c1q14).

**Steps.**
1. VM harness for the transaction cases that break activation on purpose: `pkgs.testers.runNixOSTest` exposed as `packages.x86_64-linux.dangonix-vm` (not in `checks`, so `dangonix check` stays fast) and run by `dangonix check --vm`. The node is a small NixOS with Home Manager, user `kit` and `dangonix`, switching between fixture configurations under `tests/dangonix-vm/` (a tiny host and home on the same nixpkgs, not the real host: no Foundry, no Hyprland). The VM is offline: put every fixture variant's build closure in the image (`system.includeBuildDependencies` or `virtualisation.additionalPaths`, `nix.settings.substituters = [ ]`); nixpkgs' own `nixos/tests/nixos-rebuild-*.nix` show the pattern.

**Do not.** Change the transaction code to make a case pass without saying why in the commit body. Test failures in the checkout.

**Verify (VM, `nix build --no-link .#dangonix-vm`, against the fixture flake).**
1. Changed host (`environment.etc."dangonix-test".text = "1";`), `switch`: `/etc/dangonix-test` exists; JSON `steps` are host before home.
2. `system.activationScripts.dangonixFail = "exit 1";`, `theme <other fixture theme>`: `failedStep: "host"`, `recovered: true`; system, home generation, boot entries and `state.json` unchanged.
3. Host change + `xdg.configFile."dangonix-test".text = "1";` + a `home.activation` step after `linkGeneration` that exits 1: `failedStep: "home"`, `recovered: true`; `~/.config/dangonix-test` gone; generations unchanged.
4. While a `theme` switch builds, a second `theme` and `foundry remove main` fail at once with "another … is running".

**Stop if.** The VM cannot rebuild offline: write what blocks it; the GM decides whether cases 1-4 run live instead.

**AGENTS.md.** One line: `dangonix check --vm` runs the VM transaction tests (slow; run it when transaction code changes).

**Commit.** `test(c1q15): dangonix VM transaction tests`

**GM's turn.**
- `dangonix check --vm` passes on the laptop too.
- Decide whether `hyprland` tracks release tags (`github:hyprwm/Hyprland?ref=v0.x.y`) instead of git master; tell the scribe in the project.
- Long rest: read the reviewer's findings, push `redesign`, merge into `main` as a merge commit, sync `main`.
- All good → `## c1q15 — виконано`.

---

## c1q16 — Vow of silence
meta: tier=hero effort=medium boss=no diff=leaves leaves=+noctalia-runtime-keys*,+python3*?,~hm_*noctalia*?,~kit-fish-completions?,~man-paths?

**Goal.** Noctalia telemetry is off through one named runtime key; nothing else in its `settings.toml` changes.

**Why.** [Design: Noctalia runtime state](design.md#noctalia-runtime-стан): `settings.toml` is applied last and wins over declarations.

**Files.** `profiles/noctalia/`, `lib/checks.nix`, `AGENTS.md`, `docs/progress.md`.

**Read first.** `profiles/noctalia/default.nix`.

**Preconditions.** In the Noctalia source (`nix eval --raw .#nixosConfigurations.nixos._module.specialArgs.inputs.noctalia.outPath`) confirm: the table path of `telemetry_enabled`; whether Noctalia rewrites `settings.toml` from memory (on change or exit); how it treats a missing or partial file. Unclear, or reading the path is refused → stop.

**Steps.**
1. The Noctalia module gets a named list of runtime keys (now only `telemetry_enabled = false`).
2. Script `noctalia-runtime-keys` (Python `tomlkit`, declared in Nix) sets exactly those keys in `~/.local/state/noctalia/settings.toml`, preserving format; HM activation step after `writeBoundary`.
3. If Noctalia rewrites the file from memory, the same script is also `ExecStartPre` of the Noctalia user unit.
4. Check `noctalia-runtime-keys` in `lib/checks.nix`: a `runCommand` that runs the script on three fixtures in the build sandbox (a real-looking file with other keys and comments, an empty file, a missing path) and compares each result with the expected text: only the named key differs.

**Do not.** Delete or rewrite the real `settings.toml`. Touch the palette. Run the script on files outside the build sandbox.

**Verify.** `nix build --no-link .#checks.x86_64-linux.noctalia-runtime-keys` succeeds; `scripts/closure-diff HEAD` shows no change for `home-caelestia`.

**AGENTS.md.** "Noctalia's `settings.toml` wins over declarations; enforce runtime keys only through the named list."

**Commit.** `feat(c1q16): Noctalia telemetry off`

**GM's turn.**
- `cp -a ~/.local/state/noctalia/settings.toml ~/settings.toml.bak`; `dangonix switch`; restart Noctalia.
- `telemetry_enabled` is false in the file and in Noctalia's settings UI; `diff ~/settings.toml.bak ~/.local/state/noctalia/settings.toml` shows only that line; the palette looks the same.
- All good → `## c1q16 — виконано`.

---

## c1q17 — Spirit in the iron
meta: tier=hero effort=medium boss=no diff=leaves leaves=+fwupd*,~dangonix*,+unit-fwupd*?,+*?,~*?

**Goal.** Firmware updates exist, but only on request through `dangonix firmware`.

**Why.** [Design §5 commands](design.md#команди), [§7](design.md#7-енергія-і-фон): nothing in the background.

**Files.** `hosts/nixos/configuration.nix` (or the host module that owns services), `lib/dangonix/`, `docs/progress.md`.

**Read first.** `lib/dangonix/commands.nix`.

**Steps.**
1. `services.fwupd.enable = true`; its metadata-refresh timer off (`systemd.timers.fwupd-refresh.enable = false` or the module's own option if it has one).
2. `dangonix firmware [--refresh]` (`read`, `allow`): refresh metadata only if older than 24 h (`--refresh` forces), then list devices and updates.
3. `dangonix firmware update` (`host`, `ask`, takes the lock, `reversible: false`; asks `y/N` on a TTY and needs `--yes` otherwise, [design §5 grammar](design.md#граматика)): `fwupdmgr update`.

**Verify.**
- `nix build --no-link .#checks.x86_64-linux.commands` succeeds (check 7 accepts both rows).
- `nix run . -- --dry --json firmware update` plans `fwupdmgr update` with `reversible: false` and changes nothing.
- `nix eval .#nixosConfigurations.nixos.config.systemd.timers --apply 't: t ? fwupd-refresh && t.fwupd-refresh.enable'` prints `false`.

**AGENTS.md.** No change.

**Commit.** `feat(c1q17): firmware`

**GM's turn.**
- `dangonix switch` (sudo); `dangonix firmware` lists the ThinkPad UEFI/EC; a second run within 24 h does not refresh; `systemctl list-timers | grep fwupd` is empty.
- All good → `## c1q17 — виконано`.

---

## c1q18 — Walling up the old gates
meta: tier=hero effort=medium boss=no diff=leaves leaves=-kit-profile*,-foundry*,~dangonix*?,-hm_*?,~hm_*?,~kit-fish-completions?,~man-paths?

**Goal.** `dangonix` is the only entry point.

**Why.** [Current-state: command surface](current-state.md): one action had up to five entry points.

**Files.** `justfile` (deleted), `home/theme-switcher.nix` (deleted), `scripts/list-packages.py` (deleted), `scripts/check` (deleted), `flake.nix`, `lib/repo-apps.nix`, `home/kit.nix`, `home/foundry.nix`, `home/programs/terminal.nix`, `README.md`, `.github/workflows/ci.yml`, `scripts/quest-verify`, `AGENTS.md`, `docs/progress.md`.

**Read first.** `flake.nix` (apps, `homeConfigurations`, devShell), `lib/repo-apps.nix`, `home/theme-switcher.nix`, `home/foundry.nix`, `home/programs/terminal.nix` (`shellAbbrs`), `README.md`.

**Steps.**
1. `git rm justfile home/theme-switcher.nix scripts/list-packages.py`; remove `./theme-switcher.nix` from `home/kit.nix` and `just` from the devShell.
2. Every flake app except `default` goes (`lib/repo-apps.nix` keeps only what `checks.static` and `formatter` use); `KIT_PROFILE_FLAKE`/`KIT_THEME_FLAKE` go with `theme-switcher.nix`; the `homeConfigurations.kit-<id>` outputs go (keep `homeConfigurations.kit` and `checks.home-<id>`).
3. `home/foundry.nix`: delete the `foundry*` scripts; the three desktop entries call `dangonix foundry open`, `dangonix foundry stop`, `dangonix foundry restart`.
4. `home/programs/terminal.nix`: delete the abbreviations `jc`, `jf`, `jp`, `js`, `nfu`.
5. README: replace the sections from `## Common Commands` to the end of `## FoundryVTT` with a short `dangonix` section (`dangonix help`, `switch`, `theme`, `check`, `foundry`), keeping `## Layout` and `## Package Ownership`.
6. `git rm scripts/check`; `.github/workflows/ci.yml` and `scripts/quest-verify` call `nix run . -- check …` instead; drop it from the shellcheck list.
7. `rg -n 'kit-profile|kit-theme|KIT_PROFILE_FLAKE|KIT_THEME_FLAKE|just (switch|home-switch|check|fmt|foundry-check)|foundry-status|foundry-stop|foundry-restart|scripts/check|list-packages' --glob '!docs/**'` prints nothing outside `.claude/settings.json` and `.codex/rules/` (the GM edits those).

**Do not.** Remove `homeConfigurations.kit` or `checks.home-<id>`. Edit `.claude/settings.json` or `.codex/rules/`.

**Verify.** `nix eval .#apps.x86_64-linux --apply builtins.attrNames` prints `[ "default" ]`; `nix eval .#homeConfigurations --apply builtins.attrNames` prints `[ "kit" ]`.

**AGENTS.md.** Drop every pre-dangonix command; the loop uses `dangonix check`.

**Commit.** `refactor(c1q18)!: remove old entry points`
(body: `BREAKING CHANGE: just, kit-profile, kit-theme, foundry* and the flake apps other than default are gone; use dangonix.`)

**GM's turn.**
- Delete the pre-dangonix rules from both permission files: in `.claude/settings.json` the allow rules `scripts/check`, `scripts/check *`, `foundry-status` and the ask rules `just switch`, `just home-switch`, `nix run .#switch`, `nix run .#home-switch`, `kit-profile switch *`, `kit-theme switch *`, `foundry`, `foundry-stop`, `foundry-restart`; in `.codex/rules/dangonix.rules` their counterparts. Commit as `chore(c1q18): drop old permission rules`.
- `dangonix switch`; `command -v kit-profile` fails; the three Foundry launcher entries work.
- All good → `## c1q18 — виконано`.

---

## c1q19 — True name
meta: tier=hero effort=medium boss=no diff=leaves leaves=~dangonix*,-hm_*?,+hm_*?,~hm_*?

**Goal.** Everything is named dangoNix / theme.

**Why.** Naming drift ([current-state](current-state.md)); [design §2 layout](design.md#2-структура-репо).

**Files.** every file `rg` finds in step 4, `profiles/` → `themes/` (moved), `docs/progress.md`; not `docs/` otherwise.

**Read first.** `home/options.nix`, `profiles/default.nix`, `lib/dangonix/`.

**Steps.**
1. Options `kit.*` → `dangonix.*` (including `kit.repo`); `kit.profile.*` → `dangonix.theme.*`.
2. `git mv profiles themes`; registry `themes/default.nix`; the registry attribute `profiles` → `themes` (`scripts/closure-diff` reads `themes or profiles`).
3. Identity file `~/.config/dangonix/theme-id`; lock `$XDG_RUNTIME_DIR/dangonix.lock`; env `DANGONIX_FLAKE`; flake description "dangoNix".
4. `rg -n -w 'kit\.(profile|apps|repo)|profiles/|profile-id|kit-home-activation|kitOS' --glob '!docs/**'` prints nothing.

**Do not.** Rename the Unix user `kit` or the hostname `nixos`. Add migration code (the selection lives in `state.json`).

**Verify.** `scripts/closure-diff HEAD` still compares both themes; `nix eval --raw .#homeConfigurations.kit.config.dangonix.theme.id` prints `noctalia`; `nix eval .#homeConfigurations.kit.config.xdg.configFile --apply 'f: builtins.hasAttr "dangonix/theme-id" f'` prints `true`.

**AGENTS.md.** New names (theme, `themes/`).

**Commit.** `refactor(c1q19)!: full rename`
(body: `BREAKING CHANGE: options kit.* are dangonix.*, profiles/ is themes/, the identity file is ~/.config/dangonix/theme-id.`)

**GM's turn.**
- `dangonix switch`; `cat ~/.config/dangonix/theme-id`; two competing `dangonix` commands still exclude each other.
- All good → `## c1q19 — виконано`.

---

## c1q20 — Seal of the pact ⚔️
meta: tier=hero effort=high boss=yes diff=leaves leaves=~dangonix*,+hm_*roles*?,~kit-fish-completions?

**Goal.** The theme contract exists as options, Noctalia declares every role, and `dangonix doctor` checks them live.

**Why.** [Design §3 roles](design.md#ролі-контракт). Caelestia is brought up to the contract in campaign II; until then it runs in warning mode.

**Files.** `themes/contract.nix` (new), `themes/noctalia/`, `themes/caelestia/`, `themes/default.nix`, `home/dangonix.nix`, `lib/dangonix/`, `lib/checks.nix`, `AGENTS.md`, `docs/progress.md`.

**Read first.** Design §3 in full; `themes/noctalia/binds.nix`, `themes/caelestia/`.

**Steps.**
1. `themes/contract.nix`: manifest fields (`status`; Caelestia `experimental`) and the four role kinds incl. "frontend with default"; provider roles name their user unit. `keybindings`, `clipboard`, `search` are registered in campaign II.
2. Noctalia declares every role, values from `themes/noctalia/binds.nix`.
3. Warning mode: missing roles in an experimental theme are warnings.
4. `home/dangonix.nix` writes the active theme's roles to `~/.config/dangonix/roles.json`.
5. `dangonix doctor` (`read`, `allow`): one owner of `org.freedesktop.Notifications` and it is the declared provider; a registered polkit agent (confirm the probe against polkit's interfaces; fallback: the agent's unit is active and its registration line is in the journal); a running idle provider; at most one clipboard writer. Warning-mode themes report undeclared roles as warnings.

**Verify.** `nix run . -- check --fast` shows Caelestia's missing roles as warnings only; `nix eval .#homeConfigurations.kit.config.xdg.configFile --apply 'f: builtins.hasAttr "dangonix/roles.json" f'` prints `true`; `nix run . -- --dry --json doctor` passes `jq -e .`.

**AGENTS.md.** "Experimental themes produce role warnings until Caelestia meets the contract; do not add new ones. Run `dangonix doctor` after switching a theme."

**Commit.** `feat(c1q20): contract options and doctor`

**GM's turn.**
- `dangonix switch`; `dangonix doctor` passes in Noctalia; `systemctl --user stop noctalia` → doctor fails naming notifications, polkit, idle; start it → passes.
- All good → `## c1q20 — виконано`.

---

## c1q21 — Oath of keys
meta: tier=hero effort=medium boss=no diff=none

**Goal.** Core binds are one list that calls roles; every bind has a description; `hyprland.lua` is byte-identical.

**Why.** [Design: binds are data](design.md#бінди--це-дані); today ~70 % of Noctalia's binds copy the core.

**Files.** `home/hyprland/binds.nix` (new), `home/hyprland/default.nix`, `themes/noctalia/`, `themes/caelestia/`, `docs/progress.md`.

**Read first.** `themes/noctalia/binds.nix`, `home/hyprland/lua-helpers.nix`, `tests/binds/`.

**Steps.**
1. Recreate `home/hyprland/binds.nix` as the core bind list calling roles; delete `themes/noctalia/binds.nix`.
2. Every bind is a record with a human `description` (kept in Nix, not emitted into `hyprland.lua`); every existing bind keeps its full resolved entry.
3. Caelestia sets `dangonix.hyprland.coreBinds = false` (it has no binds today and must keep none).

**Do not.** Reorder binds unless the generator would be contorted otherwise; then the sorted lists of full resolved entries must be equal, the fixture must pass, and stop: the GM switches this quest to `diff=leaves` with `~hm_*hyprland.lua*` as the only expected change.

**Verify.** `nix eval` of the bind data shows a `description` on every entry; `binds-fixture` passes.

**AGENTS.md.** No change.

**Commit.** `refactor(c1q21): binds generated from roles`

**GM's turn.**
- `dangonix switch`; `dangonix doctor` passes; a few keys behave as before.
- All good → `## c1q21 — виконано`.

---

## c1q22 — Sealing the pact
meta: tier=hero effort=medium boss=no diff=none rest=c1r3

**Goal.** Contract checks 3, 4 and 5 run for every theme, and `docs/themes.md` explains the contract.

**Why.** [Design §3 checks](design.md#перевірки-static-libchecksnix-на-кожну-тему). Ends campaign I.

**Files.** `lib/checks.nix`, `themes/contract.nix`, `docs/themes.md` (new), `AGENTS.md`, `docs/progress.md`.

**Read first.** Design §3 checks; `lib/checks.nix`, `themes/contract.nix`.

**Steps.**
1. Check 3: exactly one enabled provider per required exclusive role (no `clipboard-store` yet).
2. Check 4: role keys present, every bind has a description, no duplicate resolved keys.
3. Check 5: the first word of every role command is in the theme's `home-path/bin` or an absolute store path.
4. `docs/themes.md`: the contract, the new-theme interview checklist, deferred items (`dangonix.textSize`, the Qt QML agent skill). It links to design §3 instead of restating it.

**Verify.** Negative tests in the temporary worktree, each failing `nix run . -- --flake ./.campaign/wt-c1q22 check --fast` with the named message: unset one Noctalia role → names it; `programs.noctalia.systemd.enable = false` → check 3 reports every exclusive role Noctalia provides; `programs.waybar.enable = true` → check 3 fails; bind two actions to `mod .. " + R"` and `"SUPER + R"` → check 4 fails.

**AGENTS.md.** Point at `docs/themes.md` for theme work.

**Commit.** `feat(c1q22): contract checks and themes doc`

**GM's turn.**
- `dangonix switch`; `dangonix doctor` passes.
- Long rest: read the reviewer's findings, push `redesign`, merge into `main`, sync. The scribe then writes campaign II's quests.
- All good → `## c1q22 — виконано`.
