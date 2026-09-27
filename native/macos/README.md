# qBitX native macOS preview

qBitX is a SwiftUI interface for a bundled headless qBittorrent backend. It keeps the existing toolbar, filter sidebar, transfer table, lower detail tabs, and status bar, and uses native Liquid Glass controls. By default it uses a separate torrent library under `~/Library/Application Support/qBitX/Backend`. The original qBittorrent profile is untouched.

The main transfer, search, RSS, organization, and diagnostics workflows are implemented. **Feature parity is still under audit**; see the [feature parity audit](FEATURE_PARITY.md) for known gaps and verification limits.

## Build and open

Requires Xcode with the macOS 26 SDK or newer, plus Homebrew `cmake`, `ninja`, `qt`, `boost`, `libtorrent-rasterbar`, and `openssl@3`.

```sh
cd native/macos
./package-preview.sh
open build/qBitX.app
```

The Swift package can also be opened in Xcode through `Package.swift`. This development build uses Homebrew libraries at runtime; it is not yet a portable, signed release build.

## Isolated UI smoke test

To launch a second copy against a throwaway backend profile, duplicate the packaged app, give it a separate bundle identifier, then pass a temporary profile path and unused port:

```sh
ditto build/qBitX.app /tmp/qBitX-Test.app
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier life.andreacodin.qbitx.test' /tmp/qBitX-Test.app/Contents/Info.plist
open -n --env QBITX_TEST_BACKEND_ROOT=/tmp/qbitx-test-backend --env QBITX_TEST_BACKEND_PORT=18568 /tmp/qBitX-Test.app
```

The test variables only affect the bundled backend. Keep the test bundle identifier separate so its interface preferences do not share the regular app's settings.

## Working with an existing qBittorrent library

Use the Settings button to connect to an existing qBittorrent Web UI using an API key or username and password. Enable Web UI in the original app first. qBitX stores the credential in macOS Keychain.

## Current scope

The Transfers view supports the full set of 14 status filters, category, tag, and tracker filters; a customizable and sortable 38-column table; a pre-add metadata and file-priority dialog; multi-selection and batch actions; queue and torrent behavior controls; and the General, Trackers, Peers, HTTP Sources, Content, and Speed detail tabs. The Peers tab shows country flags and names when the backend resolves peer countries; qBitX enables this in its own library. The Speed chart offers selectable periods up to 24 hours while qBitX is running.

Search supports query history, concurrent result tabs with per-tab stop, name-only/everywhere filtering, wildcard and regex filters, seed and size ranges, customizable columns, batch downloads, and plugin-aware add options. RSS supports folders, feed management, and automatic downloader rules. Settings includes a torrent creator, cookies, session speeds, searchable backend preferences, statistics, and a filterable execution log. The preview still has open runtime and older-backend parity checks; see the [feature audit](FEATURE_PARITY.md).
