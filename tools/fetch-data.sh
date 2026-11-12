#!/usr/bin/env bash
# Bundles the FMHY wiki into Data/ so the app works offline from first launch.
set -euo pipefail
cd "$(dirname "$0")/.."
RAW=https://raw.githubusercontent.com/fmhy
mkdir -p Data
curl -fsSL "$RAW/edit/main/docs/.vitepress/transformer/headers.json" -o Data/headers.json
for f in $(grep -oE '"[a-z0-9-]+\.md"' Data/headers.json | tr -d '"'); do
  curl -fsSL "$RAW/edit/main/docs/$f" -o "Data/$f" || { echo "skip $f"; rm -f "Data/$f"; }
done
curl -fsSL https://rentry.co/FMHYB64 -o Data/rentry.html
curl -fsSL "$RAW/FMHYFilterlist/main/filterlist-domains.txt" -o Data/filterlist-domains.txt
curl -fsSL "$RAW/FMHYFilterlist/main/filterlists-reasons.json" -o Data/filterlists-reasons.json
curl -fsSL "$RAW/FMHY-SafeGuard/main/fmhy-filterlist.txt" -o Data/fmhy-filterlist.txt
