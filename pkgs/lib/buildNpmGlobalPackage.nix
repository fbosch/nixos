{ pkgs }:

let
  buildSingle = { package, version ? null, hash, meta ? {} }:
    let
      parts = pkgs.lib.splitString "@" package;
      pname = builtins.head parts;
      packageVersion = if version != null then version 
                      else if builtins.length parts > 1 then builtins.elemAt parts 1
                      else throw "Please specify version for ${pname}, e.g. { package = \"${pname}@1.0.0\"; hash = \"...\"; }";
      
      # Stage 1: Fixed-output derivation to download from npm
      downloaded = pkgs.stdenv.mkDerivation {
        name = "${pname}-${packageVersion}-downloaded";
        
        buildInputs = [ pkgs.nodejs pkgs.cacert ];
        
        dontUnpack = true;
        dontFixup = true;
        
        buildPhase = ''
          export HOME=$TMPDIR
          export npm_config_cache=$TMPDIR/npm-cache
        '';
        
        installPhase = ''
          npm install -g --prefix $out ${package}
        '';

        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = hash;
      };
    in
    # Stage 2: Normal derivation to apply fixup
    pkgs.stdenv.mkDerivation {
      name = "${pname}-${packageVersion}";
      
      dontUnpack = true;
      
      installPhase = ''
        cp -r ${downloaded} $out
        chmod -R +w $out
      '';

      meta = meta // {
        mainProgram = pname;
      };
    };

in
arg:
  if builtins.isList arg then
    map buildSingle arg
  else
    buildSingle arg
