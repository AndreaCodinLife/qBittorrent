# qBitX native macOS preview

qBitX is a SwiftUI interface for a bundled headless qBittorrent backend. It keeps the existing toolbar, filter sidebar, transfer table, lower detail tabs, and status bar, and uses native Liquid Glass controls. By default it uses a separate torrent library under `~/Library/Application Support/qBitX/Backend`. The original qBittorrent profile is untouched.

The transfer, search, RSS, organization, diagnostics, and preference workflows are implemented. The remaining parity work is packaged UI verification; see the [feature parity audit](FEATURE_PARITY.md) for its limits.

## Build and open

Requires Xcode with the macOS 26 SDK or newer, plus Homebrew `cmake`, `ninja`, `qt`, `boost`, `libtorrent-rasterbar`, and `openssl@3`.

```sh
cd native/macos
./package-preview.sh
open "$TMPDIR/qbitx-preview-$UID/qBitX.app"
```

The script prints the app path after building. It places the package in the system temporary directory so File Provider metadata in a cloud-synced workspace cannot invalidate its ad-hoc signature. The Swift package can also be opened in Xcode through `Package.swift`. This development build uses Homebrew libraries at runtime; it is not yet a portable, Developer ID signed release build.

## Isolated UI smoke test

To launch a second copy against a throwaway backend profile, duplicate the packaged app, give it a separate bundle identifier, then pass a temporary profile path and unused port:

```sh
ditto --norsrc --noextattr "$TMPDIR/qbitx-preview-$UID/qBitX.app" /tmp/qBitX-Test.app
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier life.andreacodin.qbitx.test' /tmp/qBitX-Test.app/Contents/Info.plist
xattr -cr /tmp/qBitX-Test.app
codesign --force --deep --sign - --identifier life.andreacodin.qbitx.test /tmp/qBitX-Test.app
open -n --env QBITX_TEST_BACKEND_ROOT=/tmp/qbitx-test-backend --env QBITX_TEST_BACKEND_PORT=18568 /tmp/qBitX-Test.app
```

The test variables only affect the bundled backend. Keep the test bundle identifier separate so its interface preferences do not share the regular app's settings.

## Working with an existing qBittorrent library

Use the Settings button to connect to an existing qBittorrent Web UI using an API key or username and password. Enable Web UI in the original app first. qBitX stores the credential in macOS Keychain.

## Current scope

The Transfers view supports the full set of 14 status filters, category, tag, and tracker filters; a customizable and sortable 38-column table; a pre-add metadata and file-priority dialog; multi-selection and batch actions; queue and torrent behavior controls; and the General, Trackers, Peers, HTTP Sources, Content, and Speed detail tabs. The Peers tab shows country flags and names when the backend resolves peer countries; qBitX enables this in its own library. The Speed chart offers selectable periods up to 24 hours while qBitX is running. macOS controls can show live rates in the menu bar and Dock, prevent idle sleep while active downloads or seeding are configured, and set qBitX as the default app for `.torrent` files or magnet links. Opening either type uses the same preview and add-options flow as the toolbar.

Search supports query history, concurrent result tabs with per-tab stop, name-only/everywhere filtering, wildcard and regex filters, seed and size ranges, customizable columns, batch downloads, and plugin-aware add options. RSS supports folders, feed management, and automatic downloader rules. Settings includes a torrent creator, cookies, session speeds, searchable backend preferences, statistics, and a filterable execution log. See the [feature audit](FEATURE_PARITY.md) for backend version requirements and the remaining packaged UI checks.
