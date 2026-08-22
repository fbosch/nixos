{ lib
, buildGoModule
, fetchFromGitHub
, nix-update-script
,
}:

buildGoModule rec {
  pname = "surge";
  version = "0.12.0";

  src = fetchFromGitHub {
    owner = "surge-downloader";
    repo = "surge";
    rev = "v${version}";
    hash = "sha256-N25JU3uuXr8SGNeoo0JSL0+8rGaYeQ3lWZxn+aXkJIg=";
  };

  vendorHash = "sha256-uZrSOcwfXJ9LwuHi+0wIjPBIsAdULU60GbWrJNV923s=";

  subPackages = [ "." ];

  postPatch = ''
    rm -rf vendor
  '';

  ldflags = [
    "-s"
    "-w"
    "-X github.com/surge-downloader/surge/cmd.Version=v${version}"
  ];

  env = {
    CGO_ENABLED = 0;
  };

  doInstallCheck = true;

  installCheckPhase = ''
    $out/bin/surge --version >/dev/null
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
      "--version-regex=^v([0-9]+\\.[0-9]+\\.[0-9]+)$"
    ];
  };

  postInstall = ''
    if [ -x "$out/bin/Surge" ] && [ ! -e "$out/bin/surge" ]; then
      ln -s "$out/bin/Surge" "$out/bin/surge"
    fi
  '';

  # Tests are flaky in sandboxed builds due to SQLite locking issues
  doCheck = false;

  meta = with lib; {
    description = "Blazing fast open-source TUI download manager";
    homepage = "https://github.com/surge-downloader/surge";
    changelog = "https://github.com/surge-downloader/surge/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "surge";
    maintainers = [ ];
    platforms = platforms.unix;
  };
}
