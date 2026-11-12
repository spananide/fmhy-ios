<div align="center">

<img src="Assets.xcassets/AppIcon.appiconset/icon.png" width="120" alt="FMHY icon">

# FMHY for iOS

**The whole FMHY wiki on your iPhone: searchable, offline, with a link checker.**

iOS 17+ · Free & open source · No ads · No tracking · No accounts

[**⬇️ Download the latest .ipa**](https://github.com/spananide/fmhy-ios/releases/latest) · [🐞 Send feedback](https://github.com/spananide/fmhy-ios/issues/new/choose)

<img src="docs/home.png" width="200" alt="Wiki"> <img src="docs/search.png" width="200" alt="Search"> <img src="docs/check.png" width="200" alt="Link check">

</div>

Unofficial iOS port of [FMHY for Android](https://github.com/omeg4-dev/fmhy-android) by omeg4-dev. Not affiliated with the FMHY team.

## Features
- 📴 **Offline from the first launch.** The wiki is bundled; the refresh button pulls the latest from [fmhy/edit](https://github.com/fmhy/edit).
- ⚡ **Search** that forgives typos (`stremo` finds Stremio) and understands `in:video anime`, `is:starred`, `site:github.com` and `"exact phrase"`.
- 🌟 Stars and top picks, mirrors and extra links per site, base64-hidden links decoded for you.
- 🔖 **Saved:** swipe a site to bookmark it, share your list.
- 🛡️ **Check:** paste a link to see if it is on FMHY, starred, on the unsafe list, or a clone (uses the [FMHY SafeGuard](https://github.com/fmhy/FMHY-SafeGuard) lists).
- 🔒 No analytics, no servers of mine in between. Links open in Safari view.

Not in the iOS version (yet): built-in browser with ad blocking, download manager, VirusTotal scans, widgets, changelog feed. Use a Safari content blocker (e.g. uBlock Origin Lite / AdGuard) for ads.

## Install (free, no Mac needed)
The app is not on the App Store, so you sideload the `.ipa` from [Releases](https://github.com/spananide/fmhy-ios/releases/latest).

**Option A: Sideloadly (Windows or Mac)**
1. Install [Sideloadly](https://sideloadly.io) (and iTunes on Windows, the Apple website version).
2. Plug in your iPhone, trust the computer.
3. Drag `FMHY-iOS-vX.Y.Z.ipa` into Sideloadly, enter your Apple ID, press **Start**.
4. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID.
5. On iOS 16+ also turn on Settings → Privacy & Security → **Developer Mode** and restart.

**Option B: [SideStore](https://sidestore.io) or [AltStore](https://altstore.io)** — add the `.ipa` from the Files app. SideStore refreshes by itself without a computer.

A free Apple ID signs apps for **7 days**: reopen Sideloadly (or SideStore) once a week to refresh. Free accounts can have 3 sideloaded apps at once. Your bookmarks survive a refresh.

## Feedback & bugs
Open an [issue](https://github.com/spananide/fmhy-ios/issues/new/choose) (or use "Send feedback" at the bottom of the Wiki tab). Site suggestions belong to the FMHY team: [fmhy.net/other/contributing](https://fmhy.net/other/contributing).

## Build it yourself
No Mac needed: GitHub Actions (`.github/workflows/build.yml`) fetches the wiki (`tools/fetch-data.sh`), runs the tests, takes screenshots and builds the unsigned `.ipa`. Fork the repo, push a tag like `v1.0.1`, and the release appears. Locally on a Mac: `bash tools/fetch-data.sh && xcodegen generate`.

## Credits & license
GPL-3.0-or-later, derived from [omeg4-dev/fmhy-android](https://github.com/omeg4-dev/fmhy-android) (parser, search and link-check logic ported to Swift). Wiki content by the [FMHY](https://fmhy.net) team; link lists from [FMHYFilterlist](https://github.com/fmhy/FMHYFilterlist) and [FMHY-SafeGuard](https://github.com/fmhy/FMHY-SafeGuard).

Built with the help of AI coding assistants; I design the features and review the result. If you spot a bug, please open an issue.
