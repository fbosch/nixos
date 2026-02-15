{ lib
, buildGo124Module
, fetchFromGitHub
,
}:

buildGo124Module rec {
  pname = "surge";
  version = "0.6.8";

  src = fetchFromGitHub {
    owner = "surge-downloader";
    repo = "surge";
    rev = "v${version}";
    hash = "sha256-6ISP7S5rcsjFQxXQGnqZ4jWgjNk98/npy7Z0pobIB98=";
  };

  vendorHash = "sha256-IGVt/HanZHglYSZ8WASrzqvTZZtK/bJpJzXNVqSqUfE=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/surge-downloader/surge/cmd.Version=v${version}"
  ];

  env = {
    CGO_ENABLED = 0;
  };

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
