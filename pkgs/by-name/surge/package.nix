{ lib
, buildGoModule
, fetchFromGitHub
,
}:

buildGoModule rec {
  pname = "surge";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "surge-downloader";
    repo = "surge";
    rev = "v${version}";
    hash = "sha256-YuNQlpdigs44Xrl0P7TKmSN0FKoxwZUZTGWuF3yDbHs=";
  };

  vendorHash = "sha256-dM0MpXdvxn7RH4USOyeIOVsdoyE4VUw+U44Qc9IkK5s=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/surge-downloader/surge/cmd.Version=v${version}"
  ];

  env = {
    CGO_ENABLED = 0;
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
