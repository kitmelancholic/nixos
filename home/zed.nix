{
  pkgs,
  pkgsUnstable,
  lib,
  ...
}:

let
  miriamLibre = pkgs.runCommand "miriam-libre-fonts" { } ''
    mkdir -p $out/share/fonts/truetype
    cp ${pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/MichalSahar/Miriam-Libre/abffef7af612f9eba8120919bff2d1f2ec3d590d/fonts/ttf/MiriamLibre-Regular.ttf";
      hash = "sha256-pn6orXtt4PNU1X4mxYahiWVacW+/rTcWYLCH6p2FjAk=";
    }} $out/share/fonts/truetype/MiriamLibre-Regular.ttf
    cp ${pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/MichalSahar/Miriam-Libre/abffef7af612f9eba8120919bff2d1f2ec3d590d/fonts/ttf/MiriamLibre-Bold.ttf";
      hash = "sha256-/z6ZHQyg2gIjzT7epIRZaMrribsOeLrRzXNFb3bROqk=";
    }} $out/share/fonts/truetype/MiriamLibre-Bold.ttf
  '';

  libron = pkgs.runCommand "libron-fonts-0.31" { nativeBuildInputs = [ pkgs.unzip ]; } ''
    mkdir -p $out/share/fonts/truetype
    unzip -j ${pkgs.fetchurl {
      url = "https://github.com/nicoverbruggen/libron/releases/download/v0.31/Libron.zip";
      hash = "sha256-zpo1W0axHCy+FY6RSe4To/qBPKKGYdh4cj1y9HcyQDM=";
    }} '*.ttf' -d $out/share/fonts/truetype
  '';
in
{
  home.packages = [
    miriamLibre
    libron
    pkgs.maple-mono.truetype
    pkgs.recursive
  ];

  xdg.dataFile = {
    "zed/extensions/installed/manuscript-theme".source = pkgs.fetchzip {
      url = "https://github.com/JoyAndEnjoy/zed-manuscript-theme/archive/19ae93a80e163191ab216d0c4a4bfa5206b6874c.tar.gz";
      hash = "sha256-htbnA3Iw1MgAGXHJbowhE6MlJJBsGOXT/DC+lVEJmZM=";
    };
    "zed/extensions/installed/charmed-icons".source = pkgs.fetchzip {
      url = "https://github.com/jmesrje/zed-charmed-icons/archive/883209edf9caba528fa13aa44713e425418a5e19.tar.gz";
      hash = "sha256-covjzm1XxCoI6dVU2RxesX5K3sAFeXmN8WUkqt9DO38=";
    };
  };

  programs.zed-editor = {
    enable = true;
    package = pkgsUnstable.zed-editor;

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
      vim_mode = false;
      hour_format = "hour24";
      auto_update = false;

      mouse_wheel_zoom = true;
      icon_theme = "Warm Charmed Icons";
      buffer_line_height = "comfortable";
      ui_font_weight = 400.0;
      text_rendering_mode = "platform_default";
      diff_view_style = "split";
      project_panel.dock = "left";
      git_panel.dock = "left";
      agent = {
        sidebar_side = "right";
        dock = "right";
      };

      ui_font_family = "Miriam Libre";
      ui_font_fallbacks = [ "Maple Mono" ];
      ui_font_size = 18.0;
      agent_ui_font_family = "Miriam Libre";
      agent_ui_font_fallbacks = [ "Maple Mono" ];
      agent_ui_font_size = 18;
      agent_buffer_font_family = "Maple Mono";
      agent_buffer_font_size = 20;
      markdown_preview = {
        font_family = "Libron";
        code_font_family = "Maple Mono";
      };
      buffer_font_family = "Rec Mono Casual";
      buffer_font_fallbacks = [ "Maple Mono" ];
      buffer_font_weight = 500;
      buffer_font_size = 18.75;
      semantic_tokens = "combined";

      theme = "Manuscript Dark";
      theme_overrides."Manuscript Dark".syntax = {
        type.color = "#C7B793";
        "type.builtin".color = "#CDB999";
        "type.interface".color = "#BAC2AF";
        "type.enum".color = "#C6AD93";
        enum.color = "#C3A48E";
        variant.color = "#B7A989";
        constructor.color = "#A8B5B9";
        property.color = "#B7BAA3";
        attribute.color = "#BBA6A9";
        namespace.color = "#AAA398";
        module.color = "#AAA398";
        "variable.special".color = "#ADA3B5";
        "variable.parameter".color = "#B6AB9E";
        "function.builtin".color = "#9AB0BE";
        preproc.color = "#BE8D80";
        selector.color = "#C0AA7D";
        "selector.pseudo".color = "#A99AB2";
        "string.escape".color = "#C9B7A0";
        "string.special".color = "#B7AD8F";
        "string.special.symbol".color = "#B3B58A";
        constant.color = "#C2A6B6";
        title.color = "#C8A77D";
        "title.markup".color = "#C8A77D";
        emphasis.color = "#BBA6B4";
        "emphasis.strong".color = "#C6AC87";
      };

      agent_servers = {
        codex-acp = {
          type = "custom";
          command = lib.getExe pkgsUnstable.codex-acp;
          args = [ ];
          default_config_options = {
            mode = "agent-full-access";
          };
        };
      };
    };
  };
}
