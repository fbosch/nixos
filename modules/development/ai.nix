{ inputs, ... }:
{
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
            "no-mistakes"
            "pxpipe"
            "codexbar"
          ])
        ];
      };
    };
}
