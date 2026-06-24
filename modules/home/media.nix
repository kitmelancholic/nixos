{ pkgs, ... }:

{
  programs.mpv = {
    enable = true;
    config = {
      hwdec = "auto-safe";
      vo = "gpu-next";
      gpu-api = "vulkan";
    };
  };

  home.packages = with pkgs; [
    ffmpeg # Media conversion and OBS/MPV workflow helper
    yt-dlp # Online media helper for MPV
  ];
}
