{ lib
, composeIconTheme
}:
let
  package = name: {
    inherit name;
    outPath = "/nix/store/icon-${name}";
  };

  composed = composeIconTheme {
    name = "Personal";
    base = {
      package = package "base";
      theme = "Personal";
    };
    replace.Status = {
      package = package "provider";
      theme = "Provider";
    };
    fallbacks = [
      {
        package = package "fallback";
        theme = "Fallback";
      }
    ];
    iconOverrides = [
      {
        name = "example";
        source = "/nix/store/icon-source.svg";
        context = "Applications";
        sizes = [ "16" ];
      }
    ];
  };

  script = composed.passthru.compositionScript;
in
{
  testUsesApprovedCompositionShape = {
    expr = lib.all (fragment: lib.hasInfix fragment script) [
      "active_theme=Personal"
      "/nix/store/icon-base/share/icons/Personal"
      "/nix/store/icon-provider/share/icons/Provider"
      "/nix/store/icon-fallback/share/icons/Fallback"
    ];
    expected = true;
  };

  testParsesDirectoryAndScaleMetadata = {
    expr = lib.all (fragment: lib.hasInfix fragment script) [
      "write_metadata()"
      "Directories"
      "ScaledDirectories"
      "Context"
      "Scale"
      "source_record"
      "target_directory"
    ];
    expected = true;
  };

  testReplacesCanonicalContextByMetadata = {
    expr = lib.all (fragment: lib.hasInfix fragment script) [
      "replacement_context"
      "replacement_context_key"
      "missing context"
      "cp -aL"
    ];
    expected = true;
  };

  testPreservesCrossContextLinksSafely = {
    expr = lib.hasInfix "Dereferencing keeps links which cross context boundaries" script;
    expected = true;
  };

  testOverridesRunAfterComposition = {
    expr =
      lib.hasInfix ''override_context_key'' script
      && lib.hasInfix ''cp -L "$source_icon"'' script
      && lib.hasInfix ''metadata_size * metadata_scale'' script;
    expected = true;
  };

  testMissingContextsFailClearly = {
    expr = lib.all (fragment: lib.hasInfix fragment script) [
      "is missing context"
      "missing index.theme"
    ];
    expected = true;
  };
}
