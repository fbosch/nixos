{
  flake.modules.homeManager.applications =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      anime4kShaders = lib.concatStringsSep ":" [
        "${pkgs.anime4k}/Anime4K_Clamp_Highlights.glsl"
        "${pkgs.anime4k}/Anime4K_Restore_CNN_M.glsl"
        "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_M.glsl"
        "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x2.glsl"
        "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x4.glsl"
        "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_S.glsl"
      ];
      shaderPack = "${pkgs.mpv-shim-default-shaders}/share/mpv-shim-default-shaders/shaders";
    in
    {
      programs.mpv = {
        enable = true;
        scripts = with pkgs.mpvScripts; [
          uosc
          thumbfast
        ];
        config = {
          hwdec = "nvdec";
          hwdec-extra-frames = 16;
          gpu-api = "vulkan";
          vo = "gpu-next";
          deinterlace = "auto";
          scale = "ewa_lanczossharp";
          cscale = "ewa_lanczossoft";
          dscale = "mitchell";
          autofit-larger = "80%x80%";
          save-watch-history = false;
          sub-file-paths = config.xdg.userDirs.download;
        };
        profiles = {
          anime4k = {
            profile-desc = "Anime4K upscaling";
            glsl-shaders = anime4kShaders;
          };
          fsr = {
            profile-desc = "AMD FidelityFX Super Resolution upscaling";
            glsl-shaders = "${shaderPack}/FSR.glsl";
          };
          fsrcnnx = {
            profile-desc = "FSRCNNX neural-network upscaling";
            glsl-shaders = "${shaderPack}/FSRCNNX_x2_8-0-4-1.glsl";
          };
          nvscaler = {
            profile-desc = "NVIDIA Image Scaling upscaling";
            glsl-shaders = "${shaderPack}/NVScaler.glsl";
          };
          "upscaling-off" = {
            profile-desc = "No upscaling";
            glsl-shaders = "";
          };
          interpolation = {
            profile-desc = "Display-rate interpolation";
            vf = "";
            interpolation = "yes";
            video-sync = "display-resample";
          };
          "interpolation-off" = {
            profile-desc = "No frame interpolation";
            vf = "";
            interpolation = "no";
            video-sync = "audio";
          };
          deband = {
            profile-desc = "Light debanding";
            deband = "yes";
          };
          "deband-off" = {
            profile-desc = "No debanding";
            deband = "no";
          };
          reset = {
            profile-desc = "Standard rendering";
            glsl-shaders = "";
            vf = "";
            interpolation = "no";
            video-sync = "audio";
            deband = "no";
          };
        };
      };

      xdg.configFile."mpv/scripts/profile-selector.lua".source = ./profile-selector.lua;
    };
}
