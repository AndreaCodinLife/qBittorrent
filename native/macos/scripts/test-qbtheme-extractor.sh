#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "Usage: $0 <theme-extractor> <rcc>" >&2
    exit 2
fi

extractor="$1"
rcc_path="$2"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/qbitx-theme-extractor.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

cd "$test_dir"
cat > config.json <<'JSON'
{"colors":{"TransferList.Downloading":"#123456"}}
JSON
cat > theme.qrc <<'QRC'
<RCC><qresource prefix="/"><file alias="config.json">config.json</file></qresource></RCC>
QRC
"$rcc_path" --binary theme.qrc -o valid.qbtheme

actual="$("$extractor" "$test_dir/valid.qbtheme")"
expected="$(cat config.json)"
if [[ "$actual" != "$expected" ]]; then
    echo "The extractor returned unexpected config.json contents." >&2
    exit 1
fi

printf 'not a Qt resource' > invalid.qbtheme
if "$extractor" "$test_dir/invalid.qbtheme" >/dev/null 2>&1; then
    echo "The extractor unexpectedly accepted an invalid resource." >&2
    exit 1
fi

python3 - <<'PY'
from pathlib import Path
Path("config.json").write_bytes(b"x" * (1024 * 1024 + 1))
PY
"$rcc_path" --binary theme.qrc -o oversized.qbtheme
if "$extractor" "$test_dir/oversized.qbtheme" >/dev/null 2>&1; then
    echo "The extractor unexpectedly accepted an oversized config.json." >&2
    exit 1
fi

echo "Compiled theme extraction, invalid-resource rejection, and size limits passed."
