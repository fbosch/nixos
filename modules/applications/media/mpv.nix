{
  flake.modules.homeManager.applications =
    { lib, pkgs, ... }:
    let
      anime4kShaders = lib.concatStringsSep ":" [
        "${pkgs.anime4k}/Anime4K_Clamp_Highlights.glsl"
        "${pkgs.anime4k}/Anime4K_Restore_CNN_M.glsl"
        "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_M.glsl"
        "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x2.glsl"
        "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x4.glsl"
        "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_S.glsl"
      ];
    in
    {
      programs.mpv = {
        enable = true;
        scripts = with pkgs.mpvScripts; [
          modernx
          thumbfast
        ];
        config = {
          hwdec = "nvdec";
          hwdec-extra-frames = 16;
          gpu-api = "vulkan";
          vo = "gpu-next";
          save-watch-history = false;
        };
        profiles = {
          anime4k = {
            profile-desc = "Anime4K upscaling";
            glsl-shaders = anime4kShaders;
            interpolation = "no";
            video-sync = "audio";
          };
          interpolation = {
            profile-desc = "Frame interpolation";
            glsl-shaders = "";
            interpolation = "yes";
            video-sync = "display-resample";
          };
          "anime4k-interpolation" = {
            profile-desc = "Anime4K upscaling with frame interpolation";
            glsl-shaders = anime4kShaders;
            interpolation = "yes";
            video-sync = "display-resample";
          };
          standard = {
            profile-desc = "Standard rendering";
            glsl-shaders = "";
            interpolation = "no";
            video-sync = "audio";
          };
        };
      };

      xdg.configFile."mpv/scripts/profile-selector.lua".source = ./profile-selector.lua;
    };
}
