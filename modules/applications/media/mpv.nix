{
  flake.modules.homeManager.applications =
    { lib, pkgs, ... }:
    {
      programs.mpv = {
        enable = true;
        scripts = with pkgs.mpvScripts; [
          modernx
          thumbfast
        ];
        config = {
          hwdec = "auto-safe";
          vo = "gpu-next";
        };
        profiles.anime4k = {
          glsl-shaders = lib.concatStringsSep ":" [
            "${pkgs.anime4k}/Anime4K_Clamp_Highlights.glsl"
            "${pkgs.anime4k}/Anime4K_Restore_CNN_M.glsl"
            "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_M.glsl"
            "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x2.glsl"
            "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x4.glsl"
            "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_S.glsl"
          ];
        };
      };
    };
}
