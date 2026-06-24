{ constants, ... }:

let
  inherit (constants.apps)
    archiveManager
    browser
    fileManager
    imageViewer
    mediaPlayer
    pdfViewer
    textEditor
    ;
in
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = browser.desktop;
      "x-scheme-handler/https" = browser.desktop;
      "x-scheme-handler/mailto" = browser.desktop;

      "inode/directory" = fileManager.desktop;
      "application/pdf" = pdfViewer.desktop;

      "image/jpeg" = imageViewer.desktop;
      "image/png" = imageViewer.desktop;
      "image/gif" = imageViewer.desktop;
      "image/webp" = imageViewer.desktop;
      "image/svg+xml" = imageViewer.desktop;

      "video/mp4" = mediaPlayer.desktop;
      "video/x-matroska" = mediaPlayer.desktop;
      "video/webm" = mediaPlayer.desktop;
      "video/x-msvideo" = mediaPlayer.desktop;
      "video/quicktime" = mediaPlayer.desktop;
      "audio/mpeg" = mediaPlayer.desktop;
      "audio/flac" = mediaPlayer.desktop;
      "audio/ogg" = mediaPlayer.desktop;
      "audio/wav" = mediaPlayer.desktop;

      "text/plain" = textEditor.desktop;
      "text/markdown" = textEditor.desktop;
      "application/json" = textEditor.desktop;
      "application/xml" = textEditor.desktop;

      "application/zip" = archiveManager.desktop;
      "application/x-tar" = archiveManager.desktop;
      "application/gzip" = archiveManager.desktop;
      "application/x-7z-compressed" = archiveManager.desktop;
      "application/x-rar" = archiveManager.desktop;
    };
  };
}
