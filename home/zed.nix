{ pkgs, ... }:

{
  programs.zed-editor = {
    enable = true;

    extensions = [
      "nix"
      "toml"
      "rust"
      "lua"
      "csharp"
    ];

    extraPackages = with pkgs; [
      nixd
      nil
      rust-analyzer
      nodejs
      dotnet-sdk
    ];

    userSettings = {
      vim_mode = true;
      hour_format = "hour24";
      auto_update = false;

      ui_font_size = 16;
      buffer_font_size = 16;

      theme = {
        mode = "system";
        light = "One Light";
        dark = "One Dark";
      };

      terminal = {
        shell = "bash";
      };
    };
  };
}
