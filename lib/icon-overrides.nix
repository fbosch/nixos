{ lib }:
{
  composeIconTheme =
    pkgs:
    { name
    , base
    , replace ? { }
    , fallbacks ? [ ]
    , iconOverrides ? [ ]
    ,
    }:
    let
      replacementEntries = lib.mapAttrsToList
        (
          context: source: {
            inherit context;
            package = source.package;
            theme = source.theme;
          }
        )
        replace;

      inheritedThemes = lib.unique (
        (map (replacement: replacement.theme) replacementEntries)
        ++ (map (fallback: fallback.theme) fallbacks)
      );

      extraThemes = replacementEntries ++ fallbacks;

      metadataScript = ''
        write_metadata() {
          local index_file="$1"
          local metadata_file="$2"

          ${pkgs.gawk}/bin/awk '
            function trim(value) {
              gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
              return value
            }

            function context_key(value) {
              value = tolower(value)
              gsub(/[[:space:]_-]/, "", value)
              if (value == "app" || value == "apps" || value == "application") {
                return "applications"
              }
              return value
            }

            function add_directories(value, entries, item_count, item_index, item_directory) {
              item_count = split(value, entries, ",")
              for (item_index = 1; item_index <= item_count; item_index++) {
                item_directory = trim(entries[item_index])
                if (item_directory != "" && !(item_directory in listed)) {
                  listed[item_directory] = 1
                  directories[++directory_count] = item_directory
                }
              }
            }

            BEGIN {
              section = ""
              directory_count = 0
            }

            /^[[]Icon Theme[]][[:space:]]*$/ {
              section = "Icon Theme"
              next
            }

            /^[[].*[]][[:space:]]*$/ {
              section = $0
              sub(/^\[/, "", section)
              sub(/[]][[:space:]]*$/, "", section)
              next
            }

            {
              key = $0
              value = $0
              sub(/=.*/, "", key)
              sub(/^[^=]*=/, "", value)
              key = trim(key)
              value = trim(value)

              if (section == "Icon Theme" && (key == "Directories" || key == "ScaledDirectories")) {
                add_directories(value)
              } else if (section != "") {
                metadata[section, key] = value
              }
            }

            END {
              for (item_index = 1; item_index <= directory_count; item_index++) {
                directory = directories[item_index]
                scale = metadata[directory, "Scale"]
                if (scale == "") {
                  scale = "1"
                }
                print directory "\t" context_key(metadata[directory, "Context"]) "\t" metadata[directory, "Size"] "\t" scale "\t" metadata[directory, "Type"]
              }
            }
          ' "$index_file" > "$metadata_file"
        }

        canonical_context() {
          ${pkgs.gawk}/bin/awk '{
            value = tolower($0)
            gsub(/[[:space:]_-]/, "", value)
            if (value == "app" || value == "apps" || value == "application") {
              value = "applications"
            }
            print value
          }'
        }

        has_context() {
          local metadata_file="$1"
          local context="$2"

          ${pkgs.gawk}/bin/awk -F '\t' -v context="$context" '$2 == context { found = 1; exit } END { exit(found ? 0 : 1) }' "$metadata_file"
        }

        dereference_valid_links() {
          local root="$1"
          local source_root="''${2:-$root}"
          local link relative source_link temporary

          while IFS= read -r -d $'\0' link; do
            relative="''${link#"$root"/}"
            source_link="$source_root/$relative"
            if [ -f "$link" ] || [ -f "$source_link" ]; then
              temporary="$link.deref.$$"
              if [ -f "$link" ]; then
                cp -aL "$link" "$temporary"
              else
                cp -aL "$source_link" "$temporary"
              fi
              rm -f "$link"
              mv "$temporary" "$link"
            fi
          done < <(${pkgs.findutils}/bin/find "$root" -type l -print0)
        }

        copy_tree_contents() {
          local source_root="$1"
          local target_root="$2"

          mkdir -p "$target_root"
          # Dereferencing keeps links which cross context boundaries usable in the composed output; dangling links remain intact.
          cp -a "$source_root/." "$target_root/"
          chmod -R u+w "$target_root"
          dereference_valid_links "$target_root" "$source_root"
        }

        copy_theme_tree() {
          local source_root="$1"
          local target_root="$2"
          local label="$3"

          if [ ! -f "$source_root/index.theme" ]; then
            echo "icon theme $label is missing index.theme" >&2
            exit 1
          fi

          copy_tree_contents "$source_root" "$target_root"
        }
      '';

      replacementScripts = lib.concatMapStringsSep "\n"
        (
          replacement:
          let
            replacementRoot = "${replacement.package}/share/icons/${replacement.theme}";
          in
          ''
            replacement_root=${lib.escapeShellArg replacementRoot}
            replacement_index="$replacement_root/index.theme"
            replacement_context=${lib.escapeShellArg replacement.context}
            replacement_context_key=$(printf '%s\n' "$replacement_context" | canonical_context)

            if [ ! -f "$replacement_index" ]; then
              echo "icon theme ${replacement.theme} from ${replacement.package.name} is missing index.theme" >&2
              exit 1
            fi

            replacement_metadata="$metadata_dir/replacement-$replacement_context_key.tsv"
            write_metadata "$replacement_index" "$replacement_metadata"
            if ! has_context "$replacement_metadata" "$replacement_context_key"; then
              echo "icon theme ${replacement.theme} is missing context $replacement_context in index.theme" >&2
              exit 1
            fi
            if ! has_context "$base_metadata" "$replacement_context_key"; then
              echo "base icon theme $active_theme is missing context $replacement_context in index.theme" >&2
              exit 1
            fi

            while IFS=$'\t' read -r target_directory target_context target_size target_scale target_type; do
              [ -n "$target_directory" ] || continue
              [ "$target_context" = "$replacement_context_key" ] || continue

              source_record="$(${pkgs.gawk}/bin/awk -F '\t' -v context="$replacement_context_key" -v size="$target_size" -v scale="$target_scale" '$2 == context && $3 == size && $4 == scale { print; exit }' "$replacement_metadata")"
              if [ -z "$source_record" ]; then
                # A 1x directory is a safe source for a target with another scale when no exact variant exists.
                source_record="$(${pkgs.gawk}/bin/awk -F '\t' -v context="$replacement_context_key" -v size="$target_size" '$2 == context && $3 == size { print; exit }' "$replacement_metadata")"
              fi
              if [ -z "$source_record" ]; then
                echo "icon theme ${replacement.theme} has no ${replacement.context} directory for size=$target_size scale=$target_scale; keeping $target_directory" >&2
                continue
              fi

              IFS=$'\t' read -r source_directory _source_context _source_size _source_scale _source_type <<< "$source_record"
              target_root="$active_root/$target_directory"
              source_root="$replacement_root/$source_directory"
              if [ ! -d "$source_root" ]; then
                echo "icon theme ${replacement.theme} metadata directory $source_directory does not exist" >&2
                exit 1
              fi

              rm -rf "$target_root"
              copy_tree_contents "$source_root" "$target_root"
            done < <(${pkgs.gawk}/bin/awk -F '\t' -v context="$replacement_context_key" '$2 == context' "$base_metadata")
          ''
        )
        replacementEntries;

      overrideScripts = lib.concatMapStringsSep "\n"
        (
          override:
          let
            extension = override.extension or "svg";
            sourceModeCount =
              (if override ? source then 1 else 0)
              + (if override ? useBuiltin then 1 else 0)
              + (if override ? useBuiltinFrom then 1 else 0);
            sourceExpression =
              if override ? useBuiltin then
                ''source_icon="$target_root/${override.useBuiltin}.svg"''
              else if override ? useBuiltinFrom then
                ''source_icon="$active_root/${override.useBuiltinFrom}.svg"''
              else
                ''source_icon=${override.source}'';
            sizeScripts = lib.concatMapStringsSep "\n"
              (
                requestedSize:
                ''
                  requested_size=${lib.escapeShellArg requestedSize}
                  size_matched=0
                  while IFS=$'\t' read -r directory metadata_context metadata_size metadata_scale metadata_type; do
                    [ -n "$directory" ] || continue
                    [ "$metadata_context" = "$override_context_key" ] || continue
                    size_matched=1

                    directory_basename="''${directory##*/}"
                    if [ "$requested_size" = "scalable" ]; then
                      [ "$directory_basename" = "scalable" ] || continue
                    elif [ "$requested_size" = "symbolic" ]; then
                      [ "$directory_basename" = "symbolic" ] || continue
                    else
                      [ "$metadata_size" = "$requested_size" ] || continue
                    fi

                    target_root="$active_root/$directory"
                    if [ ! -d "$target_root" ]; then
                      echo "base icon theme $active_theme metadata directory $directory does not exist" >&2
                      exit 1
                    fi

                    ${sourceExpression}
                    if [ ! -f "$source_icon" ]; then
                      echo "icon override ${override.name} source $source_icon does not exist; skipping" >&2
                      continue
                    fi

                    target_file="$target_root/${override.name}.${extension}"
                    temporary_file="$target_file.tmp.$$"
                    cp -L "$source_icon" "$temporary_file"
                    rm -f "$target_root/${override.name}.svg" "$target_root/${override.name}.png" "$target_file"
                    mv "$temporary_file" "$target_file"
                    chmod u+w "$target_file"

                    pixel_size=""
                    if [ "$requested_size" = "symbolic" ]; then
                      pixel_size=16
                    elif [[ "$metadata_size" =~ ^[0-9]+$ ]] && [[ "$metadata_scale" =~ ^[0-9]+$ ]]; then
                      pixel_size=$((metadata_size * metadata_scale))
                    fi
                    if [ "$override_extension" = "svg" ] && [ "$requested_size" != "scalable" ] && [ -n "$pixel_size" ]; then
                      ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L \
                        -u "//*[local-name()='svg']/@width" -v "$pixel_size" \
                        -u "//*[local-name()='svg']/@height" -v "$pixel_size" \
                        "$target_file" 2>/dev/null || true
                    fi
                  done < "$active_metadata"

                  if [ "$size_matched" -eq 0 ]; then
                    echo "base icon theme $active_theme has no directory for size $requested_size; skipping icon override ${override.name}" >&2
                  fi
                ''
              )
              override.sizes;
          in
          if sourceModeCount != 1 then
            throw "icon override `${override.name}` must define exactly one of source, useBuiltin, or useBuiltinFrom"
          else
            ''
              override_context=${lib.escapeShellArg override.context}
              override_extension=${lib.escapeShellArg extension}
              override_context_key=$(printf '%s\n' "$override_context" | canonical_context)
              if has_context "$active_metadata" "$override_context_key"; then
                ${sizeScripts}
              else
                echo "base icon theme $active_theme is missing context $override_context; skipping icon override ${override.name}" >&2
              fi
            ''
        )
        iconOverrides;

      inheritScript = lib.optionalString (inheritedThemes != [ ]) ''
        generated_inherits=${lib.escapeShellArg (lib.concatStringsSep "," inheritedThemes)}
        ${pkgs.gawk}/bin/awk -v generated="$generated_inherits" '
          function emit_inherits() {
            if (!in_icon_theme || emitted) {
              return
            }
            print "Inherits=" generated (existing == "" || generated == "" ? "" : ",") existing
            emitted = 1
          }

          BEGIN {
            in_icon_theme = 0
            emitted = 0
            existing = ""
          }

          /^[[]Icon Theme[]][[:space:]]*$/ {
            in_icon_theme = 1
            print
            next
          }

          /^[[].*[]][[:space:]]*$/ {
            emit_inherits()
            in_icon_theme = 0
            print
            next
          }

          {
            if (in_icon_theme && $0 ~ /^Inherits=/) {
              existing = $0
              sub(/^Inherits=/, "", existing)
              next
            }
            print
          }

          END {
            emit_inherits()
          }
        ' "$active_index" > "$active_index.tmp"
        mv "$active_index.tmp" "$active_index"
      '';

      extraThemeScripts = lib.concatMapStringsSep "\n"
        (
          extra:
          let
            sourceRoot = "${extra.package}/share/icons/${extra.theme}";
          in
          ''
            extra_theme=${lib.escapeShellArg extra.theme}
            if [ "$extra_theme" != "$active_theme" ] && [ ! -e "$icons_root/$extra_theme" ]; then
              copy_theme_tree ${lib.escapeShellArg sourceRoot} "$icons_root/$extra_theme" "$extra_theme"
            fi
          ''
        )
        extraThemes;

      compositionScript = ''
        set -euo pipefail

        icons_root="$out/share/icons"
        active_theme=${lib.escapeShellArg name}
        active_root="$icons_root/$active_theme"
        base_root=${lib.escapeShellArg "${base.package}/share/icons/${base.theme}"}
        base_index="$base_root/index.theme"
        active_index="$active_root/index.theme"
        metadata_dir="$TMPDIR/icon-theme-compose-$$"
        mkdir -p "$icons_root" "$metadata_dir"
        trap 'rm -rf "$metadata_dir"' EXIT

        ${metadataScript}

        if [ ! -f "$base_index" ]; then
          echo "base icon theme ${base.theme} from ${base.package.name} is missing index.theme" >&2
          exit 1
        fi
        # Copy the package output, rather than replaying its install phase, so composition is independent of its builder.
        copy_theme_tree "$base_root" "$active_root" ${lib.escapeShellArg base.theme}
        base_metadata="$metadata_dir/base.tsv"
        write_metadata "$active_index" "$base_metadata"
        if [ ! -s "$base_metadata" ]; then
          echo "base icon theme $active_theme has no directories listed in index.theme" >&2
          exit 1
        fi

        ${replacementScripts}

        ${inheritScript}

        ${extraThemeScripts}
        dereference_valid_links "$active_root"

        active_metadata="$metadata_dir/active.tsv"
        write_metadata "$active_index" "$active_metadata"
        ${overrideScripts}

        for theme_directory in "$icons_root"/*/; do
          if [ -f "$theme_directory/index.theme" ]; then
            ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$theme_directory" || true
          fi
        done
      '';
    in
    pkgs.runCommand "${base.package.name}-${name}-composed"
      {
        nativeBuildInputs = [ pkgs.gtk3 pkgs.xmlstarlet ];
        passthru = { inherit compositionScript; };
      }
      compositionScript;
}
