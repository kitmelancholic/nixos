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
meta: tier=hero|cleric effort=… boss=yes|no diff=<mode> [removed=<ids>] [leaves=<globs>] [rest=<tag>]
Goal           one sentence: the end state.
Why            enough context to resolve ambiguity in the steps.
Read first     files or design sections to read before editing.
Preconditions  facts to establish first; each says what to do with the outcome.
Steps          numbered and concrete; line numbers are hints (re-locate with rg).
Do not         the traps for this quest.
Verify         checks beyond scripts/quest-verify, with expected results.
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

**Models.** `tier=` names a row of the model table in `AGENTS.md` (`hero`; `cleric` for retries and for the quests whose code the rest depends on: c1q03, c1q13, c1q14; the judge behind `scripts/review` is `judge`), with a full model id per agent, so a campaign never changes model halfway. `scripts/campaign [--agent claude|codex] [--judge claude|codex]` picks the CLI; the journal records which agent and model ran each entry.

**Shared rules.** Tests that change `state.json`, `flake.lock` or Nix code on purpose run in a temporary worktree: `wt=$(mktemp -d) && git worktree add --detach "$wt" "$(git stash create)"`, then `git worktree remove --force "$wt"`; `git status` in the checkout must be unchanged afterwards. `hosts/nixos/hardware-configuration.nix` is never touched.

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
meta: tier=hero effort=medium boss=no diff=leaves leaves=+mcp-nixos*,+bash-guard*,+hm_.configdangonixhooksbash-guard,+codex*,~claude-code*?,+hm_.codex*?

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
meta: tier=hero effort=medium boss=no diff=none

**Goal.** The default theme (`.#kit`, fresh install) is `noctalia`, and the classic-only override canary is gone.

**Why.** Noctalia is the stable theme ([vision](vision.md)); the canary asserts values only `home/waybar.nix` provides and would break in c1q08.

**Read first.** `profiles/default.nix` (line 2), `flake.nix` (around lines 146-165).

**Preconditions.** Create the local tag `last-multi-theme` on `HEAD` before editing, so retired themes stay restorable (`git checkout last-multi-theme -- profiles themes …`).

**Steps.**
1. Set the registry default to `noctalia`.
2. Delete `themeOverrideCanary` and `themeOverrideCheck`.

**Do not.** Touch any theme module.

**Verify.** `nix eval .#homeConfigurations.kit.config.kit.profile.id` returns `"noctalia"`.

**AGENTS.md.** No change.

**Commit.** `feat(c1q06)!: default theme noctalia`

---

## c1q07 — Fall of the Dark Master
meta: tier=hero effort=medium boss=no diff=none removed=dms

**Goal.** The `dms` theme (Dank Material Shell) no longer exists in the repo.

**Why.** Only Noctalia and Caelestia stay ([design §3](design.md#3-теми)); every extra theme is an external input that churns.

**Read first.** `profiles/default.nix`, `flake.nix` (inputs, `profileOwnershipCheck`).

**Preconditions.** Tag `last-multi-theme` exists. Missing → `провалений кидок`.

**Steps.**
1. `git rm -r profiles/dms`; remove its registry entry.
2. Remove the `dms` input and its `follows`; `nix flake lock` must only drop `dms` nodes.
3. Remove the `dms` assertions in `profileOwnershipCheck`.
4. `rg -n dms --glob '!docs/**'` finds nothing.

**Do not.** Touch other themes or inputs. Run `nix flake update`.

**AGENTS.md.** No change.

**Commit.** `refactor(c1q07)!: retire DMS`

---

## c1q08 — Twilight of the classics
meta: tier=hero effort=medium boss=no diff=none removed=catppuccin,tokyo-night,gruvbox,kit-dark

**Goal.** The classic family is gone; only Noctalia and Caelestia remain.

**Why.** Retired by decision; `nix flake check` drops from 7 + 7 builds to 2 + 2.

**Read first.** `profiles/classic/`, `home/hyprland/settings.nix`, `flake.nix` (`selectorArchitectureCheck`, classic assertions).

**Steps.**
1. `git rm -r themes/ profiles/classic/ home/waybar.nix home/osd.nix home/power.nix home/screenshots.nix home/desktop/theme.nix home/desktop/wallpaper.nix home/hyprland/settings.nix home/hyprland/binds.nix assets/wallpapers/*`; remove their imports and registry entries.
2. Remove the `kit.apps.launcher` option and the classic assertions.
3. Remove the `readFile` assertion of `selectorArchitectureCheck` that reads `home/hyprland/settings.nix` (the rest of that check goes in c1q11).

**Do not.** Remove the Stylix import (c1q09). Touch `profiles/noctalia` or `profiles/caelestia`.

**Verify.** If anything differs for noctalia or caelestia, the classic code leaked into the shells: `провалений кидок` with the `nix-diff`.

**AGENTS.md.** Update the layout lines.

**Commit.** `refactor(c1q08)!: retire the classic family`

---

## c1q09 — Dispelling Stylix
meta: tier=hero effort=medium boss=no diff=none

**Goal.** Stylix is gone.

**Why.** Only the retired themes used it; the contract has no `stylix` value ([design §3](design.md#ролі-контракт)).

**Read first.** `lib/mk-home.nix` (line 18).

**Steps.** Remove the `stylix` input and the module import; `nix flake lock` only drops `stylix` nodes.

**Do not.** Paper over a diff. Any difference is something disabled Stylix still set: `провалений кидок` with the `nix-diff`.

**AGENTS.md.** No change.

**Commit.** `refactor(c1q09): drop Stylix`

---

## c1q10 — Cleaning the castle ⚔️
meta: tier=hero effort=medium boss=yes diff=leaves leaves=-hyprpolkitagent*,-hyprlock*?,-blueman*,-network-manager-applet*,~dbus*? rest=c1r1

**Goal.** The host keeps only what the remaining lock screens need, and the tray no longer duplicates the shells' own Wi-Fi and Bluetooth.

**Why.** After c1q08 nothing uses the classic lock stack. `services.blueman` and `networkmanagerapplet` are leftovers too: their XDG autostart entries (UWSM runs them) put blueman-applet and nm-applet in the tray next to the Wi-Fi and Bluetooth panels Noctalia and Caelestia already have, so the GM sees each twice. `bluetuith` stays as the terminal fallback. Host changes need the GM's switch, so this is act I's boss.

**Read first.** `hosts/nixos/desktop.nix` (around lines 15-18, 76, 115).

**Preconditions.** Find which PAM service the Noctalia **and** Caelestia lock screens use (read their locked sources for `pam` service names). Either uses `hyprlock` → keep `programs.hyprlock` and the `hypridle` force-disable; neither → drop both; cannot tell → `провалений кидок` with what you found.

**Steps.**
1. Remove `hyprpolkitagent` from system packages.
2. As decided: keep, or remove both `programs.hyprlock.enable = true` and `services.hypridle.enable = lib.mkForce false` with its comment.
3. Remove `blueman.enable = true` from `services` and `networkmanagerapplet` from system packages. Keep `hardware.bluetooth` and `bluetuith`.

**Do not.** Remove only one of the hyprlock / hypridle pair. Touch other PAM services. Disable `hardware.bluetooth` or NetworkManager.

**Verify.** `nix build .#nixosConfigurations.nixos.config.system.build.toplevel`. Home: no change.

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

**Read first.** `flake.nix` (all `checks`), `profiles/noctalia/binds.nix`, `home/hyprland/` .

**Steps.**
1. Add `lib/checks.nix`; `flake.nix` only wires it.
2. Delete the grep checks, hard-coded assertions and alias checks (`theme`, `hyprland`, `home`).
3. Check `registry` (design check 1): unique ids, `profiles/<family>` exists, valid manifest fields, `kit.profile.id == id`; family invariants become assertions in the family module (replacing `profileCheck`, `selectorArchitectureCheck`, `profileOwnershipCheck`, including the `launch_apps_as_systemd_services` assertion).
4. Check `host`: builds the host toplevel.
5. Bind key resolver (normalise `mod` → `SUPER`, modifier order SUPER CTRL ALT SHIFT, separator ` + `) and frozen fixture `tests/binds/<id>.json`: each entry is the full resolved bind (key, action, arguments, every flag, e.g. `{ mouse = true; }`); check `binds-fixture`.

**Do not.** Change any built output. Leave a check that greps source text.

**Verify.** `nix flake show` lists only `static`, `registry`, `binds-fixture`, `host`, `home-<id>`, `hyprland-<id>`. Negative tests in a temporary worktree: change one fixture action → `binds-fixture` fails; drop `mouse = true` from one mouse bind → fails; duplicate a registry id → `registry` fails; set an invalid `boot.kernelPackages` → `host` fails.

**AGENTS.md.** Mention that checks live in `lib/checks.nix` and the bind fixture changes only with a declared behavior change.

**Commit.** `test(c1q11): checks out of flake.nix`

---

## c1q12 — Book of choices
meta: tier=hero effort=medium boss=no diff=none

**Goal.** A tracked `state.json` holds every choice a command can make: the theme and the Foundry instances.

**Why.** [Design §4](design.md#4-statejson). Foundry uses the instances shape from the start, but with one instance `main` that maps to today's single service and data, so nothing built changes; several instances arrive in campaign II ([design §9](design.md#9-foundry-vtt)).

**Read first.** `lib/settings.nix` (lines 14-22), `hosts/nixos/foundryvtt.nix`, `home/foundry.nix`.

**Preconditions.** Locate the version table in the locked nix-foundryvtt source; confirm it carries, per version, the payload filename and hash its package uses. Not so → `провалений кидок`.

**Steps.**
1. Add `state.json`: `{ "theme": "noctalia", "foundry": { "instances": { "main": { "version": <current>, "port": <current> } } } }` and nothing else.
2. `homeConfigurations.kit` builds `state.theme`; the registry `default` goes away.
3. The host gets only `state.foundry` (via `specialArgs`). Today's Foundry module reads `instances.main`; an assertion fails evaluation with "several Foundry instances arrive in campaign II" if there is more than one, and empty `instances` disables Foundry.
4. Delete `shortVersion`, `filename`, `hash` from `lib/settings.nix`; the payload check (`foundry-check`, until c1q18) derives filename and hash from the nix-foundryvtt table.
5. Check `registry` gains "`state.json`'s theme exists".

**Do not.** Change the Foundry unit name, data dir or port.

**Verify.** `just foundry-check` passes. In a temporary worktree a version absent from the table fails evaluation with a clear message.

**AGENTS.md.** "`state.json` holds the GM's choices; change it only when asked."

**Commit.** `refactor(c1q12): state file`

---

## c1q13 — Forging dangonix ⚔️
meta: tier=cleric effort=high boss=yes diff=leaves leaves=+dangonix*,+hm_.configfishcompletionsdangonix.fish

**Goal.** `dangonix` v1 exists next to the old commands: every subcommand, the grammar, `--json` and `--dry`; the read commands and `check` work for real, and every `state`/`host` command so far only plans (`--dry`).

**Why.** The single CLI is the heart of the design: [§5](design.md#5-dangonix), [transactions](design.md#транзакції), [§6](design.md#6-стабільність). This is the first of three quests (c1q14 transactions, c1q15 VM tests); later campaigns extend this code, so its structure matters more than in any other quest.

**Read first.** Design §5 in full; `home/theme-switcher.nix`, `lib/settings.nix` (held inputs), `scripts/check`.

**Steps.**
1. `lib/dangonix/` (`default.nix`, `commands.nix` with `effect`, `agent` and `wraps` (the raw commands a row wraps, [design §11 agents](design.md#агенти); only data until campaign II), `dangonix.sh`) and `home/dangonix.nix`; `apps.default = dangonix`; option `kit.repo` (default `~/nixos`, renamed in c1q19).
2. Subcommands: `switch`, `check [--fast|--vm]` (absorbs `scripts/check`: the same steps and modes, plus `host`; `scripts/check` becomes `exec nix run "$(git rev-parse --show-toplevel)" -- check "$@"` so CI and `quest-verify` keep working), `update` (held list, reports held), `theme`, `commands`, `status`, `help`, `version`, `history` (reads the transaction journal), and `foundry` limited to one instance: `list`, `status|logs|start|stop|restart|open [main]`, where `status` and `foundry status` show only what exists by now (power, net, shield, Funnel and backup arrive with their features in campaign II and III), `import <zip>`, `upgrade main <zip>`, `add main <zip>`, `remove main`. Every command has `--json`; every non-`read` command has `--dry`. Grammar, global flags (`--yes`, `--metered-ok` included), the JSON envelope and exit codes follow [design §5 grammar](design.md#граматика).
3. In this quest every `state`/`host` command only plans: without `--dry` it refuses with exit 4 ("not available before c1q14") and changes nothing; `check --vm` refuses the same way until c1q15.

**Do not.** Remove or change any old command. Implement any `state`/`host` effect (that is c1q14).

**Verify.** `dangonix check` and `dangonix check --fast` give the same results as `scripts/check`; `dangonix theme` marks noctalia; every command in `dangonix commands --json` runs (`read` with `--json`, others with `--dry --json`) without a prompt and its output passes `jq -e .`.

**AGENTS.md.** Loop becomes `edit → nix fmt → dangonix check --fast → dangonix check → scripts/closure-diff`; discovery `dangonix commands --json`.

**Commit.** `feat(c1q13): dangonix v1 commands`

**GM's turn.**
- `just home-switch`; `dangonix status`, `dangonix help`, `dangonix --dry switch` look right to you.
- All good → `## c1q13 — виконано`.

---

## c1q14 — Tempering the blade ⚔️
meta: tier=cleric effort=high boss=yes diff=leaves leaves=~dangonix*

**Goal.** Every `state`/`host` command of `dangonix` runs as a transaction, and the permission files are generated from the command table.

**Why.** The single CLI is the heart of the design: [§5](design.md#5-dangonix), [transactions](design.md#транзакції), [§6](design.md#6-стабільність).

**Read first.** Design §5 (transactions) and §6 in full; `lib/dangonix/`; `home/theme-switcher.nix` (lock, activation).

**Steps.**
1. Every `state`/`host` command is the transaction from design §5: one lock (reuse `kit-home-activation.lock`) around snapshot, preflight, `state.json` edit, build, nvd diff, host activation, home activation, recovery, and the journal line in `~/.local/state/dangonix/journal.jsonl`.
2. Generate the `.claude/settings.json` permission block and `.codex/rules/dangonix.rules` from the command table's `agent` field + the registry (per-id ask rules) + `allow dangonix --dry …` + the hand-written non-dangonix rules from c1q05 (keep the quest-loop allow list: headless runs deny everything else); add design check 7 for both files.

**Do not.** Remove or change any old command. Test failures in the checkout.

**Verify (checkout).** `dangonix theme noctalia` leaves `git diff` empty; `dangonix --dry switch` reports no change; `sudo -u nobody dangonix switch` refuses; check 7 fails after a hand edit of either permission file.

**Verify (temporary worktree on the laptop, `dangonix --flake "$wt"`; nothing here breaks activation).**
5. `update`: held inputs byte-identical in `flake.lock`, JSON `held` lists them; `update hyprland` changes only `hyprland`; with a broken check, `update` exits non-zero and `sha256sum flake.lock` is unchanged.
6. Foundry: version in the table but not in the store → `failedStep: "preflight"` naming `dangonix foundry import <zip>`; a ZIP with one changed byte or an unsupported version is rejected with `state.json` unchanged and no GC root; `remove main` then `add main <zip>` round-trips with an empty `state.json` diff.
7. Afterwards `dangonix switch` from the checkout restores the normal system; `git -C ~/nixos status` unchanged.

**AGENTS.md.** One line on `agent` allow/ask.

**Commit.** `feat(c1q14): dangonix transactions`

**GM's turn.**
- `dangonix switch` (sudo); try `dangonix theme caelestia` and back.
- All good → `## c1q14 — виконано`.

---

## c1q15 — Trial by fire
meta: tier=hero effort=high boss=no diff=leaves leaves=~dangonix*? rest=c1r2

**Goal.** The transaction cases that break activation on purpose are tested in a VM by `dangonix check --vm`.

**Why.** Recovery after a failed host or home activation cannot be tested on the laptop without risk ([design §5 transactions](design.md#транзакції)).

**Read first.** Design §5 (transactions); `lib/dangonix/` (the transaction code from c1q14).

**Steps.**
1. VM harness for the transaction cases that break activation on purpose: `pkgs.testers.runNixOSTest` exposed as `packages.x86_64-linux.dangonix-vm` (not in `checks`, so `dangonix check` stays fast) and run by `dangonix check --vm`. The node is a small NixOS with Home Manager, user `kit` and `dangonix`, switching between fixture configurations under `tests/dangonix-vm/` (a tiny host and home on the same nixpkgs, not the real host: no Foundry, no Hyprland). The VM is offline: put every fixture variant's build closure in the image (`system.includeBuildDependencies` or `virtualisation.additionalPaths`, `nix.settings.substituters = [ ]`); nixpkgs' own `nixos/tests/nixos-rebuild-*.nix` show the pattern. Cannot make the VM rebuild work → `провалений кидок` with what blocks it; the GM decides whether cases 1-4 run live instead.

**Do not.** Change the transaction code to make a case pass without saying why in the commit body. Test failures in the checkout.

**Verify (VM, `dangonix check --vm`, against the fixture flake).**
1. Changed host (`environment.etc."dangonix-test".text = "1";`), `switch`: `/etc/dangonix-test` exists; JSON `steps` are host before home.
2. `system.activationScripts.dangonixFail = "exit 1";`, `theme <other fixture theme>`: `failedStep: "host"`, `recovered: true`; system, home generation, boot entries and `state.json` unchanged.
3. Host change + `xdg.configFile."dangonix-test".text = "1";` + a `home.activation` step after `linkGeneration` that exits 1: `failedStep: "home"`, `recovered: true`; `~/.config/dangonix-test` gone; generations unchanged.
4. While a `theme` switch builds, a second `theme` and `foundry remove main` fail at once with "another … is running".

**AGENTS.md.** One line: `dangonix check --vm` runs the VM transaction tests (slow; run it when transaction code changes).

**Commit.** `test(c1q15): dangonix VM transaction tests`

**GM's turn.**
- Decide whether `hyprland` tracks release tags (`github:hyprwm/Hyprland?ref=v0.x.y`) instead of git master; tell the scribe in the project.
- Long rest: read the reviewer's findings, push `redesign`, merge into `main` as a merge commit, sync `main`.
- All good → `## c1q15 — виконано`.

---

## c1q16 — Vow of silence
meta: tier=hero effort=medium boss=no diff=leaves leaves=+noctalia-runtime-keys*,+python3*-env?,~hm_.configsystemdusernoctalia.service?

**Goal.** Noctalia telemetry is off through one named runtime key; nothing else in its `settings.toml` changes.

**Why.** [Design: Noctalia runtime state](design.md#noctalia-runtime-стан): `settings.toml` is applied last and wins over declarations.

**Read first.** `profiles/noctalia/`.

**Preconditions.** In the locked Noctalia source confirm: the table path of `telemetry_enabled`; whether Noctalia rewrites `settings.toml` from memory (on change or exit); how it treats a missing or partial file. Unclear → `провалений кидок`.

**Steps.**
1. The Noctalia module gets a named list of runtime keys (now only `telemetry_enabled = false`).
2. Script `noctalia-runtime-keys` (Python `tomlkit`, declared in Nix) sets exactly those keys in `~/.local/state/noctalia/settings.toml`, preserving format; HM activation step after `writeBoundary`.
3. If Noctalia rewrites the file from memory, the same script is also `ExecStartPre` of the Noctalia user unit.

**Do not.** Delete or rewrite the real `settings.toml`. Touch the palette.

**Verify.** On copies in `/tmp` (a real copy, an empty file, a missing path) the script sets only the named key. Caelestia unchanged.

**AGENTS.md.** "Noctalia's `settings.toml` wins over declarations; enforce runtime keys only through the named list."

**Commit.** `feat(c1q16): Noctalia telemetry off`

**GM's turn.**
- `cp -a ~/.local/state/noctalia/settings.toml ~/settings.toml.bak`; `dangonix switch`; restart Noctalia.
- `telemetry_enabled` is false in the file and in Noctalia's settings UI; `diff ~/settings.toml.bak ~/.local/state/noctalia/settings.toml` shows only that line; the palette looks the same.
- All good → `## c1q16 — виконано`.

---

## c1q17 — Spirit in the iron
meta: tier=hero effort=medium boss=no diff=leaves leaves=+fwupd*,+unit-fwupd.service,~dangonix*

**Goal.** Firmware updates exist, but only on request through `dangonix firmware`.

**Why.** [Design §5 commands](design.md#команди), [§7](design.md#7-енергія-і-фон): nothing in the background.

**Steps.**
1. `services.fwupd.enable = true`; its metadata-refresh timer off.
2. `dangonix firmware [--refresh]` (`read`, `allow`): refresh metadata only if older than 24 h (`--refresh` forces), then list devices and updates.
3. `dangonix firmware update` (`host`, `ask`, takes the lock, `reversible: false`; asks `y/N` on a TTY and needs `--yes` otherwise, [design §5 grammar](design.md#граматика)): `fwupdmgr update`.

**Verify.** Regenerated permissions ask for `dangonix firmware update`, not for `dangonix firmware`.

**AGENTS.md.** No change.

**Commit.** `feat(c1q17): firmware`

**GM's turn.**
- `dangonix switch` (sudo); `dangonix firmware` lists the ThinkPad UEFI/EC; a second run within 24 h does not refresh; `systemctl list-timers | grep fwupd` is empty.
- All good → `## c1q17 — виконано`.

---

## c1q18 — Walling up the old gates
meta: tier=hero effort=medium boss=no diff=leaves leaves=-kit-profile*,-hm_.localbinkit-theme,-hm_kittheme-id,-foundry*,~hm_applicationsfoundryvtt*,~hm_fishconfig.fish

**Goal.** `dangonix` is the only entry point.

**Why.** [Current-state: command surface](current-state.md): one action had up to five entry points.

**Read first.** `justfile`, `flake.nix` (apps, `homeConfigurations`), `home/theme-switcher.nix`, `home/foundry.nix`, `home/programs/terminal.nix` (lines 6-13), `README.md`.

**Steps.**
1. Delete `justfile`, `just` from the devShell, every flake app except `default`, `home/theme-switcher.nix` (`kit-profile`, `kit-theme`, the `kit/theme-id` file), `KIT_PROFILE_FLAKE`/`KIT_THEME_FLAKE`, the `foundry*` scripts, `scripts/list-packages.py`, the `homeConfigurations.kit-<id>` outputs, the fish abbreviations `jc jf jp js nfu`.
2. Foundry desktop entries call `dangonix foundry open|stop|restart`.
3. Remove the pre-dangonix permission rules (the ask rules for the old commands and the `foundry-status` allow rule).
4. README: replace the command sections with a short `dangonix` section.
5. Delete `scripts/check`; `.github/workflows/ci.yml` and `scripts/quest-verify` call `nix run . -- check …` instead.

**Do not.** Remove `homeConfigurations.kit` or `checks.home-<id>`.

**AGENTS.md.** Drop every pre-dangonix command.

**Commit.** `refactor(c1q18)!: remove old entry points`

**GM's turn.**
- `dangonix switch`; `command -v kit-profile` fails; the three Foundry launcher entries work.
- All good → `## c1q18 — виконано`.

---

## c1q19 — True name
meta: tier=hero effort=medium boss=no diff=leaves leaves=-hm_kitprofile-id,+hm_dangonixtheme-id,~dangonix*

**Goal.** Everything is named dangoNix / theme.

**Why.** Naming drift ([current-state](current-state.md)); [design §2 layout](design.md#2-структура-репо).

**Steps.**
1. Options `kit.*` → `dangonix.*` (including `kit.repo`); `kit.profile.*` → `dangonix.theme.*`.
2. `git mv profiles themes`; registry `themes/default.nix`.
3. Identity file `~/.config/dangonix/theme-id`; lock `$XDG_RUNTIME_DIR/dangonix.lock`; env `DANGONIX_FLAKE`; flake description "dangoNix".

**Do not.** Rename the Unix user `kit` or the hostname `nixos`. Add migration code (the selection lives in `state.json`).

**Verify.** `scripts/closure-diff HEAD` still compares every theme.

**AGENTS.md.** New names (theme, `themes/`).

**Commit.** `refactor(c1q19)!: full rename`

**GM's turn.**
- `dangonix switch`; `cat ~/.config/dangonix/theme-id`; two competing `dangonix` commands still exclude each other.
- All good → `## c1q19 — виконано`.

---

## c1q20 — Seal of the pact ⚔️
meta: tier=hero effort=high boss=yes diff=leaves leaves=~dangonix*,+hm_.configdangonixroles.json

**Goal.** The theme contract exists as options, Noctalia declares every role, and `dangonix doctor` checks them live.

**Why.** [Design §3 roles](design.md#ролі-контракт). Caelestia is brought up to the contract in campaign II; until then it runs in warning mode.

**Read first.** Design §3 in full; `themes/noctalia/binds.nix`, `themes/caelestia/`.

**Steps.**
1. `themes/contract.nix`: manifest fields (`status`; Caelestia `experimental`) and the four role kinds incl. "frontend with default"; provider roles name their user unit. `keybindings`, `clipboard`, `search` are registered in campaign II.
2. Noctalia declares every role, values from `themes/noctalia/binds.nix`.
3. Warning mode: missing roles in an experimental theme are warnings.
4. `home/dangonix.nix` writes the active theme's roles to `~/.config/dangonix/roles.json`.
5. `dangonix doctor` (`read`, `allow`): one owner of `org.freedesktop.Notifications` and it is the declared provider; a registered polkit agent (confirm the probe against polkit's interfaces; fallback: the agent's unit is active and its registration line is in the journal); a running idle provider; at most one clipboard writer. Warning-mode themes report undeclared roles as warnings.

**Verify.** `dangonix check` shows Caelestia's missing roles as warnings only.

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

**Read first.** `themes/noctalia/binds.nix`, `tests/binds/`.

**Steps.**
1. Recreate `home/hyprland/binds.nix` as the core bind list calling roles; delete `themes/noctalia/binds.nix`.
2. Every bind is a record with a human `description` (kept in Nix, not emitted into `hyprland.lua`); every existing bind keeps its full resolved entry.
3. Caelestia sets `dangonix.hyprland.coreBinds = false`.

**Do not.** Reorder binds unless the generator would be contorted otherwise; then the sorted lists of full resolved entries must be equal, the fixture must pass, and `hm_hyprhyprland.lua` becomes the single expected change (stop with `провалений кидок` to have the GM switch this quest to `diff=leaves`).

**Verify.** `nix eval` of the bind data shows a description on every entry.

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

**Steps.**
1. Check 3: exactly one enabled provider per required exclusive role (no `clipboard-store` yet).
2. Check 4: role keys present, every bind has a description, no duplicate resolved keys.
3. Check 5: the first word of every role command is in the theme's `home-path/bin` or an absolute store path.
4. `docs/themes.md`: the contract, the new-theme interview checklist, deferred items (`dangonix.textSize`, the Qt QML agent skill). It links to design §3 instead of restating it.

**Verify.** Negative tests in a temporary worktree: unset one Noctalia role → `dangonix check --fast` names it; `programs.noctalia.systemd.enable = false` → check 3 reports every exclusive role Noctalia provides; `programs.waybar.enable = true` → check 3 fails; bind two actions to `mod .. " + R"` and `"SUPER + R"` → check 4 fails.

**AGENTS.md.** Point at `docs/themes.md` for theme work.

**Commit.** `feat(c1q22): contract checks and themes doc`

**GM's turn.**
- `dangonix switch`; `dangonix doctor` passes.
- Long rest: read the reviewer's findings, push `redesign`, merge into `main`, sync. The scribe then writes campaign II's quests.
- All good → `## c1q22 — виконано`.
