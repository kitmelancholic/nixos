{
  config,
  lib,
  pkgs,
  ...
}:

let
  look = config.dangonix.look;
  colours = [
    "black"
    "red"
    "green"
    "yellow"
    "blue"
    "magenta"
    "cyan"
    "white"
  ];

  # A Ghostty theme from the Manuscript palette Zed uses.
  fromZed =
    file: selection:
    let
      theme = lib.head (lib.importJSON "${
        import ../manuscript.nix { inherit pkgs; }
      }/themes/${file}.json").themes;
      inherit (theme) style;
      ansi =
        map (c: style."terminal.ansi.${c}") colours ++ map (c: style."terminal.ansi.bright_${c}") colours;
    in
    {
      background = style."terminal.background";
      foreground = style."terminal.foreground";
      palette = lib.imap0 (i: hex: "${toString i}=${hex}") ansi;
      cursor-color = (lib.head style.players).cursor;
      selection-background = selection;
    };
in
{
  programs = {
    fish = {
      enable = true;
      shellAbbrs = {
        jc = "just check";
        jf = "just fmt";
        jp = "just packages";
        js = "just flake-show";
        gst = "git status";
        gsw = "git switch";
        nd = "nix develop";
        nfu = "nix flake update";
      };
      interactiveShellInit = ''
        set fish_greeting
      '';
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
    };

    starship = {
      enable = true;
      enableFishIntegration = true;
      enableBashIntegration = false;
      settings = {
        add_newline = false;

        format = "$directory$git_branch$git_status$nix_shell$cmd_duration$status$line_break$character";
        right_format = "$python$nodejs$rust$dotnet";

        directory = {
          style = "blue";
          truncation_length = 3;
          truncate_to_repo = true;
        };

        git_branch = {
          format = "[$symbol$branch]($style) ";
          style = "purple";
        };

        git_status = {
          format = "[$all_status$ahead_behind]($style) ";
          style = "yellow";
        };

        nix_shell = {
          format = "[$symbol$name]($style) ";
          symbol = "nix ";
          style = "cyan";
        };

        cmd_duration = {
          min_time = 2000;
          format = "[$duration]($style) ";
          style = "yellow";
        };

        status = {
          disabled = false;
          format = "[$status]($style) ";
          style = "red";
        };

        character = {
          success_symbol = "[❯](green)";
          error_symbol = "[❯](red)";
        };

        python.format = "[$symbol$version]($style) ";
        nodejs.format = "[$symbol$version]($style) ";
        rust.format = "[$symbol$version]($style) ";
        dotnet.format = "[$symbol$version]($style) ";
        package.disabled = true;
        aws.disabled = true;
        gcloud.disabled = true;
        kubernetes.disabled = true;
      };
    };

    ghostty = {
      enable = true;
      enableFishIntegration = true;
      enableBashIntegration = true;
      themes = {
        manuscript-dark = fromZed "manuscript-dark" "#433D38";
        manuscript-light = fromZed "manuscript-light" "#E0D9C8";
      };
      settings = {
        theme = "light:${look.terminal.light},dark:${look.terminal.dark}";
        font-family = look.fonts.mono;
        font-size = look.fonts.monoSize;
        minimum-contrast = 3;
        window-padding-x = 8;
        window-padding-y = 8;
        confirm-close-surface = false;
      };
    };
  };
}
