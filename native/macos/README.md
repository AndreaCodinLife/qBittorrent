# qBitX native macOS preview

qBitX is a SwiftUI interface for a bundled headless qBittorrent backend. It keeps the existing toolbar, filter sidebar, transfer table, lower detail tabs, and status bar, and uses native Liquid Glass controls. By default it uses a separate torrent library under `~/Library/Application Support/qBitX/Backend`. The original qBittorrent profile is untouched.

The transfer, search, RSS, organization, diagnostics, and preference workflows are implemented. qBitX includes a WidgetKit extension, a live menu bar transfer control, actionable torrent notifications, and a macOS Login Items preference. The widget shows aggregate rates and torrent counts without exposing torrent names. A native Mac target cannot start ActivityKit Live Activities: Apple makes ActivityKit unavailable to macOS apps, while Live Activities shown in the Mac menu bar come from a paired iPhone app ([ActivityKit](https://developer.apple.com/documentation/ActivityKit), [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)). Appearance preferences can import qBittorrent theme colors into native controls while retaining adaptive Liquid Glass; Qt stylesheets, compiled theme resources, and custom icon files remain unsupported. See the [feature parity audit](FEATURE_PARITY.md) for its limits.

## Build and open

Requires Xcode with the macOS 26 SDK or newer, plus Homebrew `cmake`, `ninja`, `qt`, `boost`, `libtorrent-rasterbar`, and `openssl@3`. The preview script uses an Apple Development signing identity matching the current macOS account when possible, so the app and widget can share a macOS App Group container. Set `QBITX_CODE_SIGN_IDENTITY` to select a different installed identity. The script derives a team-prefixed App Group ID from the signing certificate; macOS supports these groups without a provisioning profile ([Apple documentation](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)). If no Apple Development identity is available, the script builds the app without embedding the widget extension.

```sh
cd native/macos
./package-preview.sh
open "$TMPDIR/qbitx-preview-$UID/qBitX.app"
```

The script prints the app path after building. It places the package in the system temporary directory so File Provider metadata in a cloud-synced workspace cannot invalidate its signature. The Swift package can also be opened in Xcode through `Package.swift`. This development build uses Homebrew libraries at runtime; it is not yet a portable, Developer ID signed release build.

After opening qBitX once, add **qBitX Transfers** from the macOS widget gallery to the desktop or Notification Center ([Apple's WidgetKit guide](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension) notes that the app must launch at least once for its widget to appear). qBitX shares only aggregate rates and torrent counts with the widget through its App Group container. While qBitX is running, it asks WidgetKit to refresh the displayed snapshot about once a minute; macOS controls the final refresh schedule.

In Preferences → When Starting, turn on **Launch qBitX at login**. macOS may require approval in System Settings → General → Login Items. Turn on **Show Speed in Menu Bar** in the Transfers toolbar menu to see live rates and access session pause/resume controls. Torrent notifications include Pause / Resume and Open qBitX actions.

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

The Transfers view supports the full set of 14 status filters, category, tag, and tracker filters; a customizable and sortable 38-column table; a pre-add metadata and file-priority dialog; multi-selection and batch actions; queue and torrent behavior controls; and the General, Trackers, Peers, HTTP Sources, Content, and Speed detail tabs. The Peers tab shows country flags and names when the backend resolves peer countries; qBitX enables this in its own library. The Speed chart offers selectable periods up to 24 hours while qBitX is running. macOS widgets, live menu bar controls, actionable notifications, and the Dock badge can show or control transfer activity. qBitX can launch at login, prevent idle sleep while active downloads or seeding are configured, and set itself as the default app for `.torrent` files or magnet links. Opening either type uses the same preview and add-options flow as the toolbar.

Search supports query history, concurrent result tabs with per-tab stop, name-only/everywhere filtering, wildcard and regex filters, seed and size ranges, customizable columns, batch downloads, and plugin-aware add options. RSS supports folders, feed management, and automatic downloader rules. Settings includes a torrent creator, cookies, session speeds, searchable backend preferences, statistics, and a filterable execution log. See the [feature audit](FEATURE_PARITY.md) for backend version requirements and the remaining packaged UI checks.
