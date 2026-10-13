{
  config,
  lib,
  pkgs,
  ...
}:

let
  themeName = "cream-autumn-kit";

  # Balsamiq Sans is not in nixpkgs; fetched from google/fonts at a pinned commit.
  balsamiqSans =
    let
      base = "https://raw.githubusercontent.com/google/fonts/8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/balsamiqsans";
      faces = {
        Regular = "sha256-/MnACprW54Zz+oRlN0VWkJckHZm10Th6I/OVhY7Ua34=";
        Bold = "sha256-ozAr2EJOajdwTrXiDVxaOi/YD+r1fkihnSYfjgxYNiE=";
        Italic = "sha256-Cih0cgNUCfVWrNZsHJJgR+6YKaYviLD6JzWRMyqGBt8=";
        BoldItalic = "sha256-SZlYimbe+/OecYs+2wuWW5MhV72NEyETDeBr7AzczHU=";
      };
    in
    pkgs.runCommand "balsamiq-sans-fonts" { } ''
      mkdir -p $out/share/fonts/truetype
      ${lib.concatStrings (
        lib.mapAttrsToList (face: hash: ''
          cp ${
            pkgs.fetchurl {
              url = "${base}/BalsamiqSans-${face}.ttf";
              inherit hash;
            }
          } $out/share/fonts/truetype/BalsamiqSans-${face}.ttf
        '') faces
      )}
    '';

  # "Recursive Sans Casual Static" (pkgs.recursive, installed via home/zed.nix) has
  # no Cyrillic; Chromium falls back per glyph to Balsamiq Sans, which does.
  stack = ''"Recursive Sans Casual Static", "Balsamiq Sans", system-ui, sans-serif'';

  customCss = ''
    :root {
      --font-ui: ${stack} !important;
      --font-sans: ${stack} !important;
      --font-serif: ${stack} !important;
      --font-heading: ${stack} !important;
      --font-claude-response: ${stack} !important;
      --font-mono: ${stack} !important;
      --font-code: ${stack} !important;
    }
    html, body, button, input, textarea, select {
      font-family: ${stack} !important;
    }
    .font-ui, .font-sans, .font-serif, .font-mono,
    .font-claude-response, .font-claude-response-body, .font-claude-response-title,
    code, pre, kbd, samp {
      font-family: ${stack} !important;
    }
  '';

  # Colors come from the bundled "Cream Autumn" palette; this theme only adds fonts.
  # Empty light/dark maps are kept so the engine always sees a variant pair.
  theme = {
    name = "Cream Autumn (kit fonts)";
    extends = "cream-autumn";
    light = { };
    dark = { };
    chatFont = stack;
    inherit customCss;
  };

  configDir = "${config.xdg.configHome}/Claude";
in
{
  home.packages = [ balsamiqSans ];

  # themes.d is never written by the app, so a store symlink is fine here.
  xdg.configFile."Claude/themes.d/${themeName}.json".text = builtins.toJSON theme;

  # The app persists activeTheme into claude-desktop-extra.jsonc (else .json), so
  # those files stay mutable regular files; only the activeTheme value is set.
  home.activation.claudeDesktopActiveTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -z "''${DRY_RUN:-}" ]; then
      dir="${configDir}"
      json="$dir/claude-desktop-extra.json"
      jsonc="$dir/claude-desktop-extra.jsonc"
      mkdir -p "$dir"
      if [ -f "$jsonc" ] && grep -qE '^[[:space:]]*"activeTheme"' "$jsonc"; then
        ${pkgs.gnused}/bin/sed -i -E \
          '/^[[:space:]]*\/\//! s/("activeTheme"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"${themeName}"/' \
          "$jsonc"
      elif [ -f "$json" ]; then
        if ! ${pkgs.jq}/bin/jq -e '.activeTheme == "${themeName}"' "$json" >/dev/null 2>&1; then
          tmp="$(mktemp "$dir/.claude-desktop-extra.XXXXXX")"
          if ${pkgs.jq}/bin/jq '.activeTheme = "${themeName}"' "$json" > "$tmp"; then
            mv "$tmp" "$json"
          else
            rm -f "$tmp"
            echo "claude-desktop: could not parse $json; activeTheme left unchanged" >&2
          fi
        fi
      else
        printf '{\n  "activeTheme": "${themeName}"\n}\n' > "$json"
      fi
    fi
  '';
}
