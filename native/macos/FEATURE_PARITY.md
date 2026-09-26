# qBitX feature parity audit

**Result: qBitX is not feature complete with the original qBittorrent desktop UI.**
This is a source-level audit of the `qBitX` branch against the Qt UI in this fork. “Present” means the native UI exposes the action; “Partial” means only a subset is exposed; “Missing” means there is no native control. A working backend API alone does not count as a UI feature.

The comparison uses `src/gui/mainwindow.ui`, `src/gui/transferlistwidget.cpp`, `src/gui/transferlistmodel.h`, `src/gui/properties/`, `src/gui/optionsdialog.ui`, `src/gui/search/`, and `src/gui/rss/`. The native implementation is under `native/macos/Sources/qBitX/`. This inventory is grouped by user workflow rather than listing every label in every dialog. Platform-specific actions still need a macOS behavior decision.

| Original desktop workflow | qBitX status | Gap |
| --- | --- | --- |
| Add torrent file or link | Partial | The add dialog offers save path, category, tags, stopped state, download order, management, and speed limits. Content preview and file selection before adding remain absent. |
| Start, stop, remove torrent | Present | Multi-selection and batch actions are available. |
| Transfer table | Partial | All 38 Qt transfer fields are available as customizable columns. Additional original column behavior and sort modes need review. |
| Status, category, tag, tracker filters | Partial | Basic filtering works; original has additional filter behavior and category/tag management. |
| Torrent context menu | Partial | Force start, recheck, reannounce, move location, rename, export `.torrent`, copy, and torrent options are exposed. Preview and share limits remain absent. |
| Queue management | Present | Move to top, up, down, or bottom is available. |
| Torrent behavior switches | Partial | Sequential download, first/last piece priority, automatic management, and super seeding are available. Per-torrent share limits remain absent. |
| Global session and speeds | Partial | Pause/resume and normal/alternative speed limits are available. Completion actions remain absent. |
| General detail | Partial | More metadata, availability, timing, and transfer statistics are shown; some original fields and actions remain absent. |
| Trackers detail | Partial | Add, edit, remove, and copy are available. Tier management and other tracker actions remain absent. |
| Peers detail | Partial | Live peers, country flags, client, progress, rates, add, ban, and copy are available. Additional original columns and actions remain absent. |
| HTTP sources detail | Partial | Add, remove, and copy are available. Editing remains absent. |
| Content detail | Partial | File priority, selection, and rename are available. Preview remains absent. |
| Speed detail | Partial | Recent per-torrent rate graph; original graph controls and history options are absent. |
| Search | Partial | Category and plugin selection, stopping jobs, and plugin install/enable/remove/update are available. Multiple search tabs and history remain absent. A fresh qBitX library has no search plugins installed. |
| RSS | Partial | Feed edit/remove/refresh, article filtering, and mark-read controls are available. Folders and automatic downloader rules remain absent. |
| Preferences | Partial | Backend preferences are exposed in nine grouped sections with generic controls. Specialized dialogs, explanations, and validation from the Qt UI remain absent. |
| Torrent creator | Partial | A native dialog creates v1, v2, or hybrid torrents from a local file or folder. The original creator has more options, task management, and drag-and-drop. |
| Cookies and plugin management | Partial | Cookie add/edit/remove and search plugin management are available. Other plugin dialogs and original workflow details remain absent. |
| Statistics and execution log | Partial | Both are available in Settings. Original statistics fields and log controls still need an action-by-action comparison. |
| UI customization and other menus | Missing | Original toolbar/sidebar/status bar options, lock, and other desktop menu actions are not exposed. |

The original Qt UI may contain more minor actions inside dialogs and context menus than this workflow inventory captures. Full parity requires an action-by-action checklist for those surfaces and runtime verification on macOS. Until each item is implemented or explicitly accepted as a macOS-specific omission, qBitX must be described as a **preview**, not as a replacement with all original features.

## Completion gate

1. Inventory every action and setting from the original macOS Qt app, including context menus and dialogs.
2. Provide a native control and backend behavior for each item, or record a deliberate macOS exception.
3. Test each action with an isolated qBittorrent profile and verify that the result persists after restarting both the app and backend.
4. Verify large torrent lists, multiple selections, active transfers, Search, RSS, and accessibility with the actual macOS app.
