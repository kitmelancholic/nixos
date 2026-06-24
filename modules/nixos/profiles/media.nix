{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    ffmpeg # Media inspection/conversion and OBS workflow helper
    yt-dlp # Online media helper for MPV
  ];
}
