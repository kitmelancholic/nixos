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
          style = "orange";
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
      settings = {
        window-padding-x = 8;
        window-padding-y = 8;
        confirm-close-surface = false;
      };
    };
  };
}
