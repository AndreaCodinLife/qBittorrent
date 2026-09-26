# qBitX native macOS preview

qBitX is a SwiftUI interface for a bundled headless qBittorrent backend. It keeps the existing toolbar, filter sidebar, transfer table, lower detail tabs, and status bar, and uses native Liquid Glass controls. By default it uses a separate torrent library under `~/Library/Application Support/qBitX/Backend`. The original qBittorrent profile is untouched.

**Feature parity is incomplete.** See the [feature parity audit](FEATURE_PARITY.md) for the original desktop features that still need native controls.

## Build and open

Requires Xcode with the macOS 26 SDK or newer, plus Homebrew `cmake`, `ninja`, `qt`, `boost`, `libtorrent-rasterbar`, and `openssl@3`.

```sh
cd native/macos
./package-preview.sh
open build/qBitX.app
```

The Swift package can also be opened in Xcode through `Package.swift`. This development build uses Homebrew libraries at runtime; it is not yet a portable, signed release build.

## Working with an existing qBittorrent library

Use the Settings button to connect to an existing qBittorrent Web UI using an API key or username and password. Enable Web UI in the original app first. qBitX stores the credential in macOS Keychain.

## Current scope

The Transfers view supports status, category, tag, and tracker filters; a customizable 38-column table; a pre-add options dialog for URL or file torrents; multi-selection and batch actions; queue and torrent behavior controls; and the General, Trackers, Peers, HTTP Sources, Content, and Speed detail tabs. The Peers tab shows country flags and names when the backend resolves peer countries; qBitX enables this in its own library. The Speed chart shows recent rates for the selected torrent.

Search uses enabled qBittorrent search plugins, which can be installed and managed in the Search view. RSS lists feeds and articles, lets you manage feeds, and adds an article's torrent to the library. Settings includes a local torrent creator, cookies, session speeds, backend preferences, statistics, and the execution log. The preview does not yet expose every preference or management action from the Qt interface.
