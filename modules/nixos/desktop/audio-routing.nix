{
  programs.dconf.enable = true;

  services.pipewire.extraConfig.pipewire."60-stream-mix" = {
    "context.objects" = [
      {
        factory = "adapter";
        args = {
          "factory.name" = "support.null-audio-sink";
          "node.name" = "stream_mix";
          "node.description" = "Stream Mix";
          "media.class" = "Audio/Sink";
          "audio.position" = [
            "FL"
            "FR"
          ];
        };
      }
    ];
  };
}
