{ lib
, pkgs
, composeIconTheme
}:
let
  basePackage = pkgs.runCommand "icon-theme-compose-base" { } ''
    root="$out/share/icons/Personal"
    mkdir -p "$root/vendor/application-16" "$root/vendor/application-16@2x" "$root/base/status-normal" "$root/base/status-hidpi"
    cat > "$root/index.theme" <<'EOF'
[Icon Theme]
Name=Personal
Comment=Composition fixture
Directories=vendor/application-16,base/status-normal,base/status-hidpi
ScaledDirectories=vendor/application-16@2x
Inherits=base

[vendor/application-16]
Size=16
Scale=1
Context=Applications
Type=Fixed

[vendor/application-16@2x]
Size=16
Scale=2
Context=Applications
Type=Fixed

[base/status-normal]
Size=16
Scale=1
Context=Status
Type=Fixed

[base/status-hidpi]
Size=16
Scale=2
Context=Status
Type=Fixed
EOF
    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><title>base-app</title></svg>' > "$root/vendor/application-16/app.svg"
    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><title>base-app-2x</title></svg>' > "$root/vendor/application-16@2x/app.svg"
    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><title>stale-status</title></svg>' > "$root/base/status-normal/status.svg"
    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><title>stale-status-2x</title></svg>' > "$root/base/status-hidpi/status.svg"
  '';

  providerPackage = pkgs.runCommand "icon-theme-compose-provider" { } ''
    root="$out/share/icons/Provider"
    mkdir -p "$root/provider/status-small" "$root/provider/status-hidpi" "$root/provider/application-small"
    cat > "$root/index.theme" <<'EOF'
[Icon Theme]
Name=Provider
Directories=provider/status-small,provider/status-hidpi,provider/application-small

[provider/status-small]
Size=16
Scale=1
Context=Status
Type=Fixed

[provider/status-hidpi]
Size=16
Scale=2
Context=Status
Type=Fixed

[provider/application-small]
Size=16
Scale=1
Context=Applications
Type=Fixed
EOF
    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><title>provider-app</title></svg>' > "$root/provider/application-small/app.svg"
    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><title>provider-status</title></svg>' > "$root/provider/status-small/status.svg"
    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><title>provider-status-2x</title></svg>' > "$root/provider/status-hidpi/status.svg"
    ln -s ../application-small/app.svg "$root/provider/status-small/cross-context.svg"
  '';

  fallbackPackage = pkgs.runCommand "icon-theme-compose-fallback" { } ''
    root="$out/share/icons/Fallback"
    mkdir -p "$root/fallback/16"
    cat > "$root/index.theme" <<'EOF'
[Icon Theme]
Name=Fallback
Directories=fallback/16

[fallback/16]
Size=16
Scale=1
Context=Status
Type=Fixed
EOF
    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><title>fallback</title></svg>' > "$root/fallback/16/fallback.svg"
  '';

  externalOverride = pkgs.writeText "icon-theme-compose-override.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><title>external</title></svg>
  '';

  composed = composeIconTheme {
    name = "Personal";
    base = {
      package = basePackage;
      theme = "Personal";
    };
    replace.Status = {
      package = providerPackage;
      theme = "Provider";
    };
    fallbacks = [
      {
        package = fallbackPackage;
        theme = "Fallback";
      }
    ];
    iconOverrides = [
      {
        name = "external";
        source = externalOverride;
        context = "Applications";
        sizes = [ "16" ];
      }
      {
        name = "copied";
        useBuiltin = "app";
        context = "Applications";
        sizes = [ "16" ];
      }
      {
        name = "cross-copy";
        useBuiltinFrom = "vendor/application-16/app";
        context = "Status";
        sizes = [ "16" ];
      }
    ];
  };

  missingContext = composeIconTheme {
    name = "Personal-missing";
    base = {
      package = basePackage;
      theme = "Personal";
    };
    replace.Missing = {
      package = providerPackage;
      theme = "Provider";
    };
  };

  missingContextTest = ''
    set +e
    result="$TMPDIR/missing-result"
    out="$result" ${pkgs.bash}/bin/bash -c ${lib.escapeShellArg missingContext.passthru.compositionScript} 2> "$TMPDIR/missing-error"
    status=$?
    set -e
    test "$status" -ne 0
    grep -F 'missing context Missing' "$TMPDIR/missing-error"
  '';
in
pkgs.runCommand "icon-theme-compose-check" { } ''
  set -euo pipefail

  active="${composed}/share/icons/Personal"
  test "$(cat "$active/base/status-normal/status.svg")" = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><title>provider-status</title></svg>'
  test "$(cat "$active/base/status-hidpi/status.svg")" = '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><title>provider-status-2x</title></svg>'
  grep -F '<title>external</title>' "$active/vendor/application-16/external.svg"
  grep -F 'width="16" height="16"' "$active/vendor/application-16/external.svg"
  grep -F '<title>external</title>' "$active/vendor/application-16@2x/external.svg"
  grep -F 'width="32" height="32"' "$active/vendor/application-16@2x/external.svg"
  grep -F '<title>base-app</title>' "$active/vendor/application-16/copied.svg"
  grep -F '<title>base-app</title>' "$active/base/status-normal/cross-copy.svg"
  test ! -L "$active/base/status-normal/cross-context.svg"
  test -f "${composed}/share/icons/Fallback/index.theme"
  grep -F 'Inherits=Provider,Fallback,base' "$active/index.theme"

  ${missingContextTest}
  touch "$out"
''
