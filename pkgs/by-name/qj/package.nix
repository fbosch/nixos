{ fetchFromGitHub
, jq
, lib
, rustPlatform
,
}:

rustPlatform.buildRustPackage rec {
  pname = "qj";
  version = "0.1.4";

  src = fetchFromGitHub {
    owner = "6";
    repo = "qj";
    rev = "v${version}";
    hash = "sha256-npzYmq6IWiH3YLreiKTX3bFILfUHb5wo055MsPCnuYI=";
  };

  cargoHash = "sha256-RBPK+w0RxoD7JG4/yuwZMEn9SgxsRCWVRlyT+Z52Um4=";

  nativeCheckInputs = [ jq ];

  meta = with lib; {
    description = "Fast jq-compatible JSON processor powered by simdjson";
    homepage = "https://github.com/6/qj";
    changelog = "https://github.com/6/qj/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "qj";
    maintainers = [ ];
    platforms = platforms.unix;
    sourceProvenance = with sourceTypes; [ fromSource ];
  };
}
