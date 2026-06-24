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
      rust-analyzer # Rust language server
      nodejs
      dotnet-sdk
      csharp-ls # C# language server
      omnisharp-roslyn # C# language tooling fallback
      netcoredbg # .NET debugger
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
        shell = "fish";
      };
    };
  };
}
