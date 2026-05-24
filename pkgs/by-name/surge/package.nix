{ lib
, buildGoModule
, fetchFromGitHub
,
}:

buildGoModule rec {
  pname = "surge";
  version = "0.8.6";

  src = fetchFromGitHub {
    owner = "surge-downloader";
    repo = "surge";
    rev = "v${version}";
    hash = "sha256-o0GtuzqhCv39PRHeH1VXq4NLDgJoAQagIMlAkljY/Is=";
  };

  vendorHash = "sha256-tXJUr/URQZC+tNq+HOIuinaqbeElJMPWQH/MG1rY80I=";

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
