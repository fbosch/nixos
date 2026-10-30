{ pkgs
, credentials ? builtins.fromJSON (builtins.readFile ../modules/development/ai/nono/scripts/credentials.json)
, ipcRestricted ? false
,
}:
let
  base = builtins.fromJSON (builtins.readFile ../modules/development/ai/nono/scripts/profile.json);
  captureCommand = source:
    if source.type == "file" then
    # Nono resolves executable symlinks; explicit dispatch preserves the coreutils applet.
      [ "${pkgs.coreutils}/bin/coreutils" "--coreutils-prog=cat" source.path ]
    else if source.type == "command" then
      [ "${pkgs.${source.package}}/bin/${source.program}" ] ++ source.args
    else
      throw "Unsupported Pi credential source: ${source.type}";
in
base // {
  linux = base.linux // pkgs.lib.optionalAttrs ipcRestricted {
    af_unix_mediation = "pathname";
    sandbox_policy = "landlock";
  };
  network = base.network // {
    credentials = builtins.attrNames credentials;
    custom_credentials = builtins.mapAttrs
      (name: definition: definition.route // { credential_key = "cmd://${name}"; })
      credentials;
  };
  credential_capture = builtins.mapAttrs
    (_: definition: definition.capture // { command = captureCommand definition.source; })
    credentials;
}
