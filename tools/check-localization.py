#!/usr/bin/env python3
"""Compares string catalogs against the keys the compiler actually emits.

Swift builds keys from interpolation: `Text("Selected \\(a) · \\(b)")` becomes
"Selected %@ · %@", not "Selected %1$@ · %2$@". A hand-written catalog entry
that guesses wrong never matches anything and fails silently — the app just
shows English. This check makes that failure loud.
"""
import json
import pathlib
import subprocess
import sys

TARGETS = [("Cleaner", "Cleaner/Resources/Localizable.xcstrings"),
           ("CleanerKit", "CleanerKit/Resources/Localizable.xcstrings")]


def object_root() -> pathlib.Path:
    settings = subprocess.run(
        ["xcodebuild", "-workspace", "Cleaner.xcworkspace", "-scheme", "Cleaner",
         "-destination", "platform=macOS", "-showBuildSettings"],
        capture_output=True, text=True, check=True).stdout
    for line in settings.splitlines():
        if " OBJROOT = " in line:
            return pathlib.Path(line.split(" = ", 1)[1].strip())
    raise SystemExit("OBJROOT not found")


def emitted_keys(root: pathlib.Path, target: str) -> set[str]:
    found: set[str] = set()
    for file in root.rglob("*.stringsdata"):
        if file.name.startswith("ExtractedAppShortcuts"):
            continue
        # The innermost target directory, so "Cleaner" does not match
        # the "CleanerKit.build" nested inside "Cleaner.build".
        if f"/{target}.build/Objects-normal/" not in str(file):
            continue
        for entries in json.loads(file.read_text()).get("tables", {}).values():
            for entry in entries:
                key = entry.get("key") if isinstance(entry, dict) else entry
                if key:
                    found.add(key)
    return found


def main() -> int:
    subprocess.run(
        ["xcodebuild", "-workspace", "Cleaner.xcworkspace", "-scheme", "Cleaner",
         "-destination", "platform=macOS", "SWIFT_EMIT_LOC_STRINGS=YES", "build"],
        capture_output=True, text=True, check=True)

    root = object_root()
    failed = False

    for target, catalog_path in TARGETS:
        actual = emitted_keys(root, target)
        catalog = json.loads(pathlib.Path(catalog_path).read_text())
        listed = set(catalog["strings"])
        languages = {language
                     for entry in catalog["strings"].values()
                     for language in entry["localizations"]}

        missing = sorted(actual - listed)
        extra = sorted(listed - actual)
        untranslated = sorted(
            key for key, entry in catalog["strings"].items()
            if set(entry["localizations"]) != languages)

        print(f"{target}: {len(actual)} keys in code, {len(listed)} in catalog, "
              f"languages: {', '.join(sorted(languages))}")
        for label, items in (("not in catalog", missing),
                             ("in catalog but unused", extra),
                             ("missing a language", untranslated)):
            if items:
                failed = True
                print(f"  {label}:")
                for item in items:
                    print(f"    {item}")

    print("localization is consistent" if not failed else "localization has gaps")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
