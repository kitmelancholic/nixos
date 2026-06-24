{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver # VAAPI driver for newer Intel iGPUs
      intel-vaapi-driver # Legacy Intel VAAPI fallback
      intel-compute-runtime # Intel GPU compute runtime
      vpl-gpu-rt # Intel oneVPL runtime for media acceleration
    ];
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  environment.systemPackages = with pkgs; [
    libva-utils # VAAPI diagnostics
    vulkan-tools # Vulkan diagnostics
  ];
}
