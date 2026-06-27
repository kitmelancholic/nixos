let
  selectedDefault = import ./selected.nix;
  selectedOverride =
    if builtins.pathExists ./local-selected.nix then import ./local-selected.nix else selectedDefault;
  themes = {
    catppuccin = {
      name = "Catppuccin";
      polarity = "dark";
      wallpaper = ../assets/wallpapers/catppuccin.png;
      base16Scheme = {
        scheme = "Catppuccin Mocha";
        author = "Catppuccin";
        base00 = "1e1e2e";
        base01 = "181825";
        base02 = "313244";
        base03 = "45475a";
        base04 = "585b70";
        base05 = "cdd6f4";
        base06 = "f5e0dc";
        base07 = "b4befe";
        base08 = "f38ba8";
        base09 = "fab387";
        base0A = "f9e2af";
        base0B = "a6e3a1";
        base0C = "94e2d5";
        base0D = "89b4fa";
        base0E = "cba6f7";
        base0F = "f2cdcd";
      };
    };

    tokyo-night = {
      name = "Tokyo Night";
      polarity = "dark";
      wallpaper = ../assets/wallpapers/tokyo-night.png;
      base16Scheme = {
        scheme = "Tokyo Night";
        author = "Tokyo Night";
        base00 = "1a1b26";
        base01 = "16161e";
        base02 = "2f3549";
        base03 = "444b6a";
        base04 = "787c99";
        base05 = "a9b1d6";
        base06 = "cbccd1";
        base07 = "d5d6db";
        base08 = "f7768e";
        base09 = "ff9e64";
        base0A = "e0af68";
        base0B = "9ece6a";
        base0C = "7dcfff";
        base0D = "7aa2f7";
        base0E = "bb9af7";
        base0F = "c0caf5";
      };
    };

    gruvbox = {
      name = "Gruvbox";
      polarity = "dark";
      wallpaper = ../assets/wallpapers/gruvbox.png;
      base16Scheme = {
        scheme = "Gruvbox Dark";
        author = "Dawid Kurek";
        base00 = "282828";
        base01 = "3c3836";
        base02 = "504945";
        base03 = "665c54";
        base04 = "bdae93";
        base05 = "d5c4a1";
        base06 = "ebdbb2";
        base07 = "fbf1c7";
        base08 = "fb4934";
        base09 = "fe8019";
        base0A = "fabd2f";
        base0B = "b8bb26";
        base0C = "8ec07c";
        base0D = "83a598";
        base0E = "d3869b";
        base0F = "d65d0e";
      };
    };

    kit-dark = {
      name = "Kit Dark";
      polarity = "dark";
      wallpaper = ../assets/wallpapers/kit-dark.png;
      base16Scheme = {
        scheme = "Kit Dark";
        author = "kitOS";
        base00 = "141414";
        base01 = "1f1f1f";
        base02 = "2b2b2b";
        base03 = "555555";
        base04 = "888888";
        base05 = "ffffff";
        base06 = "f4f4f4";
        base07 = "ffffff";
        base08 = "ff4d4d";
        base09 = "ff9f1c";
        base0A = "ffb347";
        base0B = "98c379";
        base0C = "56b6c2";
        base0D = "ff9f1c";
        base0E = "c678dd";
        base0F = "d19a66";
      };
    };
  };
in
{
  selected = selectedOverride;
  inherit themes;
  active =
    if builtins.hasAttr selectedOverride themes then
      themes.${selectedOverride}
    else
      throw "Unknown theme '${selectedOverride}' in themes/selected.nix or themes/local-selected.nix";
}
