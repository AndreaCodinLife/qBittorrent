#!/usr/bin/env python3
"""Build native SwiftUI string catalogs from qBittorrent's translation sources."""

from __future__ import annotations

import argparse
import collections
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


SWIFT_STRING = re.compile(r'"((?:\\.|[^"\\])*)"')
UNTRANSLATED = {"unfinished", "vanished", "obsolete"}


def swift_string_keys(source_root: Path) -> set[str]:
    keys: set[str] = set()
    for source_file in sorted((source_root / "native/macos/Sources/qBitX").glob("*.swift")):
        for match in SWIFT_STRING.finditer(source_file.read_text(encoding="utf-8")):
            value = match.group(1)
            if not value or "\\(" in value or "\\n" in value or len(value) > 120:
                continue
            keys.add(value.replace('\\"', '"').replace("\\\\", "\\"))
    return keys


def locale_name(catalog: Path, document: ET.Element) -> str | None:
    locale = document.attrib.get("language")
    if locale:
        # qBittorrent's Simplified Chinese catalog is named `zh`, while its
        # preference API exposes the same language as `zh_CN`.
        return "zh_CN" if locale == "zh" else locale
    suffix = catalog.stem.removeprefix("qbittorrent_")
    return None if suffix == "en" else suffix


def translations_for(catalog: Path, keys: set[str]) -> dict[str, str]:
    root = ET.parse(catalog).getroot()
    candidates: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)

    for message in root.findall(".//message"):
        if message.attrib.get("numerus") == "yes":
            continue
        source = message.findtext("source", default="")
        translation = message.find("translation")
        if source not in keys or translation is None or translation.attrib.get("type", "") in UNTRANSLATED:
            continue
        value = "".join(translation.itertext())
        if value.strip():
            candidates[source][value] += 1

    return {source: counts.most_common(1)[0][0] for source, counts in candidates.items()}


def quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_root", type=Path)
    parser.add_argument("output_root", type=Path)
    args = parser.parse_args()

    keys = swift_string_keys(args.source_root)
    catalogs = sorted((args.source_root / "src/lang").glob("qbittorrent_*.ts"))
    args.output_root.mkdir(parents=True, exist_ok=True)

    for catalog in catalogs:
        document = ET.parse(catalog).getroot()
        locale = locale_name(catalog, document)
        if not locale:
            continue
        translations = translations_for(catalog, keys)
        if not translations:
            continue
        localization_dir = args.output_root / f"{locale}.lproj"
        localization_dir.mkdir(parents=True, exist_ok=True)
        output = localization_dir / "Localizable.strings"
        lines = [f"{quote(source)} = {quote(value)};" for source, value in sorted(translations.items())]
        output.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"{locale}: {len(translations)} strings")


if __name__ == "__main__":
    main()
