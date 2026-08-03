{ inputs, ... }:
{
  flake.modules.nixos.development = {
    nix.settings = {
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
    };
  };

  flake.modules.homeManager.development =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      optionalLocalPackages =
        names:
        lib.pipe names [
          (builtins.filter (name: lib.hasAttr name pkgs.local))
          (builtins.map (name: pkgs.local.${name}))
        ];

      llmAgentPackages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
        claude-code
        codex
        copilot-cli
        openspec
        opencode
        agent-browser
        rtk
        plannotator
        pi
      ];

    in
    {
      config = {
        home.packages = lib.flatten [
          llmAgentPackages
          (with pkgs; [
            tesseract
            herdr
          ])
          (optionalLocalPackages [
            "headroom"
            "graphify"
            "no-mistakes"
            "pxpipe"
          ])
        ];
      };
    };
}
