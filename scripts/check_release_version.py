#!/usr/bin/env python3
import argparse
import os
import plistlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PLIST = ROOT / "SkillsManager" / "Info.plist"
PROJECT_FILE = ROOT / "SkillsManager.xcodeproj" / "project.pbxproj"
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    return 1


def read_plist(path):
    try:
        with path.open("rb") as handle:
            return plistlib.load(handle)
    except FileNotFoundError:
        raise ValueError(f"{path} does not exist")
    except plistlib.InvalidFileException as error:
        raise ValueError(f"{path} is not a valid plist: {error}")


def required(plist, key, label):
    value = plist.get(key)
    if value in (None, ""):
        raise ValueError(f"missing {label} ({key})")
    return str(value)


def release_bundle_id():
    env_value = os.environ.get("PRODUCT_BUNDLE_IDENTIFIER")
    if env_value:
        return env_value

    if not PROJECT_FILE.exists():
        return None

    matches = set()
    for line in PROJECT_FILE.read_text(encoding="utf-8").splitlines():
        match = re.match(r"\s*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", line)
        if match:
            value = match.group(1).strip().strip('"')
            if not value.endswith("Tests"):
                matches.add(value)
    return matches.pop() if len(matches) == 1 else None


def expand_bundle_id(source_value):
    if "$(" not in source_value:
        return source_value
    if source_value == "$(PRODUCT_BUNDLE_IDENTIFIER)":
        value = release_bundle_id()
        if value:
            return value
    raise ValueError(
        "cannot resolve source CFBundleIdentifier; set PRODUCT_BUNDLE_IDENTIFIER"
    )


def app_info_path(app):
    path = Path(app)
    if path.name == "Info.plist":
        return path
    return path / "Contents" / "Info.plist"


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Validate release tag and built app version against source Info.plist."
    )
    parser.add_argument("--tag", help="release tag, expected to be v{CFBundleShortVersionString}")
    parser.add_argument("--app", help="path to a built .app bundle or its Contents/Info.plist")
    args = parser.parse_args(argv)

    try:
        source = read_plist(SOURCE_PLIST)
        short = required(source, "CFBundleShortVersionString", "short version")
        build = required(source, "CFBundleVersion", "build version")
        bundle_id = expand_bundle_id(required(source, "CFBundleIdentifier", "bundle id"))

        if not SEMVER.fullmatch(short):
            return fail(f"source short version must be MAJOR.MINOR.PATCH, got {short}")

        if args.tag and args.tag != f"v{short}":
            return fail(f"--tag must be v{short}, got {args.tag}")

        details = [f"source {short} ({build})"]
        if args.tag:
            details.append(f"tag {args.tag}")

        if args.app:
            app_plist_path = app_info_path(args.app)
            app = read_plist(app_plist_path)
            checks = {
                "CFBundleShortVersionString": short,
                "CFBundleVersion": build,
                "CFBundleIdentifier": bundle_id,
            }
            for key, expected in checks.items():
                actual = str(app.get(key, ""))
                if actual != expected:
                    return fail(f"{app_plist_path}: {key} must be {expected}, got {actual}")
            details.append(f"app {app_plist_path.parent.parent.name}")

    except ValueError as error:
        return fail(str(error))

    print("ok: " + ", ".join(details))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
