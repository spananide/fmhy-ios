# FMHY for iOS

Unofficial iOS port of [omeg4-dev/fmhy-android](https://github.com/omeg4-dev/fmhy-android). The whole FMHY wiki, offline, searchable, with bookmarks and a link checker. SwiftUI, iOS 17+, no dependencies.

- **Wiki**: all sections, headings, stars (⭐/🌟), mirrors and extra links, base64 links decoded. Pull to refresh from fmhy/edit (jsDelivr fallback).
- **Search**: typo-tolerant, filters `in:video`, `is:starred`, `site:github.com`, `"exact phrase"`.
- **Saved**: bookmarks, shareable list.
- **Check**: paste a link, see whether it is on FMHY, starred, unsafe or a clone (FMHY SafeGuard lists).
- Links open in Safari view. Not ported: built-in browser/adblock, downloads, VirusTotal, widgets, changelog feed.

## Build

No Mac needed: GitHub Actions (`.github/workflows/build.yml`) fetches the wiki (`tools/fetch-data.sh`), runs the tests, takes screenshots and builds an unsigned `FMHY.ipa` (artifact `build`). Sideload with Sideloadly + a free Apple ID.

Licensed GPL-3.0, derived from fmhy-android (GPL-3.0). Wiki content by the FMHY team.
