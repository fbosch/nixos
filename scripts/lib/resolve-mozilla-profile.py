#!/usr/bin/env python3

from __future__ import annotations

import configparser
import os
import sys
from pathlib import Path


def read_ini(path: Path) -> configparser.ConfigParser | None:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        with path.open(encoding="utf-8-sig") as handle:
            parser.read_file(handle)
    except (OSError, configparser.Error) as error:
        print(f"resolve-mozilla-profile: unable to read {path}: {error}", file=sys.stderr)
        return None
    return parser


def unique_existing(paths: list[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[str] = set()
    for path in paths:
        normalized = os.path.normpath(str(path))
        if normalized in seen or not path.is_dir():
            continue
        seen.add(normalized)
        result.append(path)
    return result


def resolve_path(profile_root: Path, raw_path: str) -> Path:
    path = Path(raw_path).expanduser()
    return path if path.is_absolute() else profile_root / path


def resolve_profile(profile_root: Path) -> Path | None:
    profiles_ini = profile_root / "profiles.ini"
    profiles = read_ini(profiles_ini) if profiles_ini.is_file() else None
    if profiles is None:
        return None

    registered_paths: list[Path] = []
    default_profile_paths: list[Path] = []
    paths_by_raw_value: dict[str, Path] = {}

    for section in profiles.sections():
        if not section.startswith("Profile"):
            continue

        raw_path = profiles.get(section, "Path", fallback="").strip()
        if not raw_path:
            continue

        is_relative = profiles.getboolean(section, "IsRelative", fallback=True)
        path = profile_root / raw_path if is_relative else Path(raw_path).expanduser()
        registered_paths.append(path)
        paths_by_raw_value[raw_path] = path

        if profiles.getboolean(section, "Default", fallback=False):
            default_profile_paths.append(path)

    install_paths: list[Path] = []
    for section in profiles.sections():
        if not section.startswith("Install"):
            continue
        raw_path = profiles.get(section, "Default", fallback="").strip()
        if raw_path:
            install_paths.append(paths_by_raw_value.get(raw_path, resolve_path(profile_root, raw_path)))

    installs_ini = profile_root / "installs.ini"
    if installs_ini.is_file():
        installs = read_ini(installs_ini)
        if installs is not None:
            for section in installs.sections():
                raw_path = installs.get(section, "Default", fallback="").strip()
                if raw_path:
                    install_paths.append(paths_by_raw_value.get(raw_path, resolve_path(profile_root, raw_path)))

    install_defaults = unique_existing(install_paths)
    profile_defaults = unique_existing(default_profile_paths)

    if len(install_defaults) == 1:
        return install_defaults[0]

    if len(install_defaults) > 1:
        matching_profile_defaults = [path for path in profile_defaults if path in install_defaults]
        if len(matching_profile_defaults) == 1:
            return matching_profile_defaults[0]
        print(
            f"resolve-mozilla-profile: multiple install defaults in {profile_root}; skipping",
            file=sys.stderr,
        )
        return None

    if len(profile_defaults) == 1:
        return profile_defaults[0]

    if len(profile_defaults) > 1:
        print(
            f"resolve-mozilla-profile: multiple default profiles in {profile_root}; skipping",
            file=sys.stderr,
        )
        return None

    registered = unique_existing(registered_paths)
    if len(registered) == 1:
        return registered[0]

    if len(registered) > 1:
        print(
            f"resolve-mozilla-profile: no unique default profile in {profile_root}; skipping",
            file=sys.stderr,
        )

    return None


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: resolve-mozilla-profile PROFILE_ROOT", file=sys.stderr)
        return 2

    profile = resolve_profile(Path(sys.argv[1]))
    if profile is not None:
        print(profile)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
