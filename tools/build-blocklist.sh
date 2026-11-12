#!/usr/bin/env bash
# Converts ad/tracker filter lists into Safari content-blocking JSON (Data/blocklist-N.json). macOS only.
set -euo pipefail
cd "$(dirname "$0")/.."
W=$(mktemp -d)
# the released binary needs its resource bundle next to it, so build from source (bundle lands beside the tool)
git clone -q --depth 1 --branch v4.3.1 https://github.com/AdguardTeam/SafariConverterLib "$W/src"
(cd "$W/src" && swift build -q -c release --product ConverterTool)
TOOL="$W/src/.build/release/ConverterTool"
for u in \
  https://easylist.to/easylist/easylist.txt \
  https://easylist.to/easylist/easyprivacy.txt \
  "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext" \
  https://raw.githubusercontent.com/fmhy/FMHYFilterlist/main/filterlist.txt; do
  curl -fsSL "$u" >> "$W/rules.txt"; echo >> "$W/rules.txt"
done
"$TOOL" convert --safari-version 17 --advanced-blocking false \
  --input-path "$W/rules.txt" --safari-rules-json-path "$W/all.json"
rm -f Data/blocklist-*.json
python3 - "$W/all.json" <<'PY'
import json, sys
rules = json.load(open(sys.argv[1]))
n = 50000  # well under WebKit's 150k-rules-per-list limit
for i in range(0, len(rules), n):
    json.dump(rules[i:i+n], open(f"Data/blocklist-{i//n}.json", "w"), separators=(",", ":"))
print(len(rules), "rules in", (len(rules)+n-1)//n, "files")
PY
