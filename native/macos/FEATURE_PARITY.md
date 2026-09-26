# qBitX feature parity audit

**Result: qBitX is not feature complete with the original qBittorrent desktop UI.**
This is a source-level audit of the `qBitX` branch against the Qt UI in this fork. “Present” means the native UI exposes the action; “Partial” means only a subset is exposed; “Missing” means there is no native control. A working backend API alone does not count as a UI feature.

The comparison uses `src/gui/mainwindow.ui`, `src/gui/transferlistwidget.cpp`, `src/gui/transferlistmodel.h`, `src/gui/properties/`, `src/gui/optionsdialog.ui`, `src/gui/search/`, and `src/gui/rss/`. The native implementation is under `native/macos/Sources/qBitX/`. This inventory is grouped by user workflow rather than listing every label in every dialog. Platform-specific actions still need a macOS behavior decision.

| Original desktop workflow | qBitX status | Gap |
| --- | --- | --- |
| Add torrent file or link | Partial | Adds immediately; original add dialog offers save path, category, tags, content selection, and torrent options before adding. |
| Start, stop, remove torrent | Partial | Available for one selected torrent; original supports multi-selection and related batch actions. |
| Transfer table | Partial | qBitX has 9 columns; the Qt transfer model defines 38 columns, plus column visibility and resizing controls. |
| Status, category, tag, tracker filters | Partial | Basic filtering works; original has additional filter behavior and category/tag management. |
| Torrent context menu | Missing | Force start, force recheck, force reannounce, move location, rename, export `.torrent`, preview, content management, copy variants, and torrent-specific options are absent. |
| Queue management | Missing | Move to top, up, down, or bottom is absent. |
| Torrent behavior switches | Missing | Sequential download, first/last piece priority, automatic torrent management, super seeding, and per-torrent share limits are absent. |
| Global session and speeds | Missing | Pause/resume session, global and alternative speed limits, and completion actions are absent. |
| General detail | Partial | Basic name, status, size, rates, ratio, and path are shown; the original has more metadata, availability, timing, and transfer statistics. |
| Trackers detail | Partial | Read-only list; add, edit, remove, tier, and tracker actions are absent. |
| Peers detail | Partial | Live peers, country flags, client, progress, and rates appear; original has additional columns plus add, ban, and copy actions. |
| HTTP sources detail | Partial | Read-only list; add, edit, remove, and copy actions are absent. |
| Content detail | Partial | Read-only file list; priority, selection, rename, and preview actions are absent. |
| Speed detail | Partial | Recent per-torrent rate graph; original graph controls and history options are absent. |
| Search | Partial | One query and result list; original has category/plugin selection, multiple search tabs, stopping jobs, plugin management, and history. A fresh qBitX library has no search plugins installed. |
| RSS | Partial | Add/view feeds and add article torrents; original has folders, feed edit/remove, filtering, mark read controls, and automatic downloader rules. |
| Preferences | Missing | qBitX only offers backend connection settings; original has Behavior, Downloads, Connection, Speed, BitTorrent, Search, RSS, WebUI, and Advanced pages. |
| Torrent creator | Missing | No native creator dialog. |
| Cookies and plugin management | Missing | No native management dialogs. |
| Statistics and execution log | Missing | No native statistics or log views. |
| UI customization and other menus | Missing | Original toolbar/sidebar/status bar options, lock, and other desktop menu actions are not exposed. |

The original Qt UI may contain more minor actions inside dialogs and context menus than this workflow inventory captures. Full parity requires an action-by-action checklist for those surfaces and runtime verification on macOS. Until each item is implemented or explicitly accepted as a macOS-specific omission, qBitX must be described as a **preview**, not as a replacement with all original features.

## Completion gate

1. Inventory every action and setting from the original macOS Qt app, including context menus and dialogs.
2. Provide a native control and backend behavior for each item, or record a deliberate macOS exception.
3. Test each action with an isolated qBittorrent profile and verify that the result persists after restarting both the app and backend.
4. Verify large torrent lists, multiple selections, active transfers, Search, RSS, and accessibility with the actual macOS app.
