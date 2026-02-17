{ pkgs, lib }:

{
  # Apply icon overrides to an icon theme package
  #
  # Parameters:
  #   basePackage: The icon theme package to apply overrides to
  #   overrides: List of override specifications
  #   themeName: Name of the icon theme (used to find theme directories)
  #
  # Override specification format:
  # {
  #   name = "icon-name";              # Icon filename to replace (without .svg)
  #   sizes = [ "16" "22" "scalable" ];# Size directories to apply override to
  #   context = "apps";                # Icon context (apps, places, actions, etc.)
  #
  #   # One of the following three options:
  #   useBuiltin = "other-icon";       # Use icon from same context/size
  #   useBuiltinFrom = "path/to/icon"; # Use icon from different path (relative to theme dir)
  #   source = /path/to/icon.svg;      # Use custom icon from filesystem
  # }
  applyIconOverrides =
    { basePackage
    , overrides
    , themeName
    ,
    }:
    pkgs.stdenv.mkDerivation {
      name = "${basePackage.name}-with-overrides";
      inherit (basePackage) src;

      # Add xmlstarlet for SVG attribute manipulation
      nativeBuildInputs = (basePackage.nativeBuildInputs or [ ]) ++ [ pkgs.xmlstarlet ];

      # Inherit the original package's build configuration
      dontBuild = basePackage.dontBuild or true;
      dontFixup = basePackage.dontFixup or false;

      # Inherit the original installPhase completely
      installPhase = basePackage.installPhase or ''
        runHook preInstall
        mkdir -p $out
        cp -r . $out/
        runHook postInstall
      '';

      # Apply icon overrides AFTER the base package installation completes
      postInstall = (basePackage.postInstall or "") + ''
        # Apply custom icon overrides
        ${lib.concatMapStringsSep "\n" (
          override: ''
            for theme_dir in $out/share/icons/${themeName}*; do
              ${lib.concatMapStringsSep "\n" (
                size: ''
                  size_dir="$theme_dir/${override.context}/${size}"
                  if [ -d "$size_dir" ]; then
                    ${
                      if override ? useBuiltin then
                        ''
                          # Use existing icon from same context/size as replacement
                          if [ -f "$size_dir/${override.useBuiltin}.svg" ]; then
                            rm -f "$size_dir/${override.name}.svg"
                            cp -f "$size_dir/${override.useBuiltin}.svg" "$size_dir/${override.name}.svg"
                            echo "Overriding ${override.name}.svg with ${override.useBuiltin}.svg in $size_dir"
                          fi
                        ''
                      else if override ? useBuiltinFrom then
                        ''
                          # Use existing icon from different context/directory as replacement
                          source_icon="$theme_dir/${override.useBuiltinFrom}.svg"
                          if [ -f "$source_icon" ]; then
                            # Determine target size for resizing
                            target_size=""
                            case "${size}" in
                              16) target_size="16" ;;
                              22) target_size="22" ;;
                              24) target_size="24" ;;
                              32) target_size="32" ;;
                              48) target_size="48" ;;
                              64) target_size="64" ;;
                              scalable) target_size="64" ;;  # Default scalable size
                              symbolic) target_size="16" ;;  # Symbolic icons are typically 16px
                              *) target_size="16" ;;
                            esac

                            # Copy and resize SVG by modifying width/height attributes
                            # This preserves all colors, gradients, and vector quality
                            # Remove existing file/symlink first to ensure clean override
                            rm -f "$size_dir/${override.name}.svg"
                            cp "$source_icon" "$size_dir/${override.name}.svg"

                            # Update width and height attributes if not scalable
                            if [ "${size}" != "scalable" ]; then
                              ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L \
                                -u "//*[local-name()='svg']/@width" -v "$target_size" \
                                -u "//*[local-name()='svg']/@height" -v "$target_size" \
                                "$size_dir/${override.name}.svg" 2>/dev/null || true
                              echo "Overriding ${override.name}.svg from ${override.useBuiltinFrom}.svg (resized to $target_size) in $size_dir"
                            else
                              echo "Overriding ${override.name}.svg with ${override.useBuiltinFrom}.svg in $size_dir"
                            fi
                          fi
                        ''
                      else
                        ''
                          # Use custom icon from assets
                          if [ -f "${override.source}" ]; then
                            # Determine target size for resizing
                            target_size=""
                            case "${size}" in
                              16) target_size="16" ;;
                              22) target_size="22" ;;
                              24) target_size="24" ;;
                              32) target_size="32" ;;
                              48) target_size="48" ;;
                              64) target_size="64" ;;
                              scalable) target_size="64" ;;
                              symbolic) target_size="16" ;;
                              *) target_size="16" ;;
                            esac

                            # Copy and resize custom SVG by modifying width/height attributes
                            # Remove existing file/symlink first to ensure clean override
                            rm -f "$size_dir/${override.name}.svg"
                            cp "${override.source}" "$size_dir/${override.name}.svg"

                            if [ "${size}" != "scalable" ]; then
                              ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L \
                                -u "//*[local-name()='svg']/@width" -v "$target_size" \
                                -u "//*[local-name()='svg']/@height" -v "$target_size" \
                                "$size_dir/${override.name}.svg" 2>/dev/null || true
                              echo "Overriding ${override.name}.svg with custom icon (resized to $target_size) in $size_dir"
                            else
                              echo "Overriding ${override.name}.svg with custom icon in $size_dir"
                            fi
                          fi
                        ''
                    }
                  fi
                ''
              ) override.sizes}
            done
          ''
        ) overrides}

        # Update icon cache if gtk-update-icon-cache is available
        if command -v gtk-update-icon-cache &> /dev/null; then
          for dir in $out/share/icons/*/; do
            if [ -f "$dir/index.theme" ]; then
              ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$dir" || true
            fi
          done
        fi
      '';
    };
}
