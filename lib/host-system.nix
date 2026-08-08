{ lib }:
{ system
, hostName ? null
, hostType ? null
,
}:
let
  hostLabel = if hostName == null then "Host" else "Host `${hostName}`";
in
if system == null then
  throw "${hostLabel} must define system"
else if builtins.isString system == false then
  throw "${hostLabel} system must be a string"
else
  let
    subject = if hostName == null then "Host system" else "Host `${hostName}` system";
    evaluated = builtins.tryEval (
      let
        platform = lib.systems.elaborate system;
        result = {
          normalized = platform.system;
          inherit (platform) isDarwin isLinux;
        };
      in
      builtins.deepSeq result result
    );
  in
  if evaluated.success == false then
    throw "${subject} `${system}` is not a valid Nix system"
  else if system != evaluated.value.normalized then
    throw "${subject} `${system}` must use the canonical Nix system `${evaluated.value.normalized}`"
  else if evaluated.value.isLinux == false && evaluated.value.isDarwin == false then
    throw "${subject} `${system}` must target Linux or Darwin"
  else if hostType != null && hostType != "nixos" && hostType != "darwin" then
    throw "Unknown host type `${hostType}`"
  else if hostType == "nixos" && evaluated.value.isLinux == false then
    throw "Host `${hostName}` is registered as nixos but system `${system}` is not Linux"
  else if hostType == "darwin" && evaluated.value.isDarwin == false then
    throw "Host `${hostName}` is registered as darwin but system `${system}` is not Darwin"
  else
    system
