fmt:
    nix fmt

check:
    nix run .#check

hyprland-check:
    nix run .#hyprland-check

theme-check:
    nix run .#theme-check

switch:
    nix run .#switch

packages:
    @if command -v python3 >/dev/null; then python3 scripts/list-packages.py; else nix develop -c python3 scripts/list-packages.py; fi

packages-json:
    @if command -v python3 >/dev/null; then python3 scripts/list-packages.py --json; else nix develop -c python3 scripts/list-packages.py --json; fi

theme name="":
    @if command -v python3 >/dev/null; then python3 scripts/themectl.py theme "{{name}}"; else nix develop -c python3 scripts/themectl.py theme "{{name}}"; fi

wallpaper name="":
    @if command -v python3 >/dev/null; then python3 scripts/themectl.py wallpaper "{{name}}"; else nix develop -c python3 scripts/themectl.py wallpaper "{{name}}"; fi

deadnix:
    nix develop -c deadnix --fail --exclude hosts/nixos/hardware-configuration.nix .

statix:
    nix develop -c statix check --ignore hosts/nixos/hardware-configuration.nix

flake-show:
    nix flake show --no-write-lock-file

flake-metadata:
    nix flake metadata --no-write-lock-file
