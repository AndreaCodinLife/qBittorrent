# qBitX desktop feature parity audit

This checklist compares the native macOS preview with the desktop workflows in this qBittorrent source tree. “Present” means the main workflow is available in qBitX; “Partial” records a known limitation or a smaller workflow that still needs review. The Web API cannot expose every internal Qt behavior, so a native screen alone does not establish exact parity.

| Original desktop workflow | qBitX status | Current coverage and remaining work |
| --- | --- | --- |
| Add torrent file, magnet, or URL | Present | Preview metadata and files, set per-file priorities, save location and incomplete path, category/tags, rename, queue position, seed mode, stop condition, content layout, sequential/first-last priority, speed limits, and stopped/automatic management options before adding. A remote server may not implement the metadata-preview API. |
| Start, stop, force start, remove | Present | Single and multi-selection commands and confirmation on removal are available. |
| Transfer table | Present | The 38 Qt transfer fields can be shown, hidden, reordered, and sorted. Numeric fields use numeric sorting. |
| Status, category, tag, and tracker filters | Present | All 14 Qt status filters, trackerless and per-tracker filters, plus warning/tracker-error/other-error filters are shown with counts. Tracker-status filters can be hidden or shown separately; empty filters can be hidden. Categories include nested paths and filters include descendants. |
| Category and tag management | Present | Create, edit, and remove categories and tags; create subcategories, remove unused entries, assign categories, and add/remove tags across multi-selection. Category share limits are editable. |
| Torrent context menu and behavior | Present | Preview, open destination, move/rename, category and mixed-state tag assignment, queue controls, recheck/reannounce, tracker details, sequential and first/last priority, automatic management, super seeding, per-torrent options, copy/export, and remove are exposed. |
| Global session and speeds | Present | Pause/resume, normal and alternative speed limits, and completion actions are available. macOS sleep/restart/shutdown actions use a native confirmation and system event; hibernate is unavailable on macOS. |
| General details | Present | The native tab displays qBittorrent's torrent-property fields, hashes, connection counts and limits, rates, totals, share metrics, piece metadata, timing, and the downloaded-piece and availability diagrams. |
| Tracker details | Present | Add, edit, remove, tier changes, move between tiers, and copy are available. Force reannounce is available from the torrent context menu. |
| Peer details | Present | Country flags and names, IP/port, connection, flags, client and peer ID client, progress, rates, totals, relevance, contribution, and active files are displayed; add, ban, and copy actions are available. Country information depends on the backend's country database. |
| HTTP sources | Present | Add, edit, remove, and copy are available. |
| Content details | Present | Name, size, availability, progress, and priority are displayed. Multiple files can be selected for priority changes; rename and media preview are available. |
| Speed details | Present | The session graph includes total, payload, overhead, DHT, and tracker rates in both directions, with per-series toggles and 1-minute through 24-hour ranges. History is sampled while qBitX is running and is not persisted across launches. |
| Search | Present | Search categories and plugins, query history, multiple result tabs, stop, and plugin install/update/enable/remove are available. Search still requires compatible qBittorrent search plugins. |
| RSS and automatic downloader | Present | Feed/folder management, article actions, rules, enable/disable, rename/clone/remove, matching articles, import/export, category/tags/path, stopped state, layout, and priority options are available. |
| Preferences | Partial | Backend preferences remain accessible in grouped native settings. Specialized Qt editors, descriptions, validation, and connection-specific behavior need further audit. |
| Torrent creator | Present | v1/v2/hybrid format, piece size, private mode, source/comment, trackers and web seeds, hidden-file handling, task history, export, and task removal are available. |
| Cookies and plugin management | Present | Cookie editing and search-plugin management are available. |
| Statistics and execution log | Present | qBittorrent session statistics fields and log severity/search filters are available. |
| Menus, toolbar, and window layout | Present | Toolbar visibility and label style, filter sidebar, details pane, status bar, speed in title bar, interface lock, About/help links, and session/tools menus are available. Native File, Transfers, Navigate, and Settings commands include macOS keyboard shortcuts for core actions. |

## Verification completed

- Swift package build on the macOS 26 SDK and C++ backend build.
- Isolated Web API checks for RSS rules and folders, categories/tags, per-torrent limits, torrent creation options, metadata preview/file priorities, tracker tiers, session statistics, bulk tag assignment/removal, and multi-file priority changes. These checks used temporary qBittorrent profiles rather than the user's normal profile.
- `git diff --check`.

## Remaining parity gate

1. Exercise the packaged native app on macOS with large lists, multi-selection, active transfers, Search, RSS, and accessibility enabled.
2. Finish a preference-by-preference comparison with the Qt options dialog; the generic native preference editor still lacks some specialized explanations and validation.
3. Record minimum backend-version requirements for preview and tracker-summary endpoints, then verify older supported remote qBittorrent versions.

The source and isolated API checks cover the main transfer, search, RSS, organization, and diagnostic workflows. This audit remains open until the packaged macOS UI, accessibility, backend compatibility, and specialized preference screens are checked.
