{ pkgs, ... }:

let
  preCommitWrapper = pkgs.writeShellApplication {
    name = "pre-commit-wrapper";
    runtimeInputs = with pkgs; [
      actionlint
      deadnix
      git
      gum
      nixpkgs-fmt
      shellcheck
      shfmt
      statix
      treefmt
    ];
    text = builtins.readFile ./scripts/pre-commit-wrapper.sh;
  };
in

{
  packages = with pkgs; [
    actionlint
    deadnix
    git
    gum
    just
    nil
    nixd
    nixpkgs-fmt
    shellcheck
    shfmt
    statix
    treefmt
  ];

  scripts = {
    lint.exec = ''
      bash ./scripts/lint.sh
    '';

    fmt.exec = ''
      treefmt --no-cache
    '';

    fmt-check.exec = ''
      treefmt --no-cache --fail-on-change
    '';

    check-service-ports.exec = ''
      bash ./scripts/check-service-ports.sh
    '';

    pre-commit-wrapper.exec = ''
      bash ./scripts/pre-commit-wrapper.sh
    '';
  };

  git-hooks.hooks.pre-commit-wrapper = {
    enable = true;
    name = "repo pre-commit wrapper";
    entry = "${preCommitWrapper}/bin/pre-commit-wrapper";
    language = "system";
    pass_filenames = false;
  };
}
