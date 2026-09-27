# qBitX desktop feature parity audit

This checklist compares the native macOS preview with the desktop workflows in this qBittorrent source tree. “Present” means the main workflow is available in qBitX; “Partial” records a known limitation or a smaller workflow that still needs review. The Web API cannot expose every internal Qt behavior, so a native screen alone does not establish exact parity.

| Original desktop workflow | qBitX status | Current coverage and remaining work |
| --- | --- | --- |
| Add torrent file, magnet, or URL | Present | Preview metadata and files, set per-file priorities, save location and incomplete path, category/tags, rename, queue position, seed mode, stop condition, content layout, sequential/first-last priority, speed limits, and stopped/automatic management options before adding. A remote server may not implement the metadata-preview API. |
| Start, stop, force start, remove | Present | Single and multi-selection commands and confirmation on removal are available. |
| Transfer table | Present | The 38 Qt transfer fields can be shown, hidden, reordered, and sorted. Numeric fields use numeric sorting. |
| Status, category, tag, and tracker filters | Present | All 14 Qt status filters, trackerless and per-tracker filters, plus warning/tracker-error/other-error filters are shown with counts. Tracker-status filters can be hidden or shown separately; empty filters can be hidden. Category filters include descendants. Tracker summaries refresh every 15 seconds and are reused between full transfer-list polls. |
| Category and tag management | Present | Create, edit, and remove categories and tags; create subcategories, remove unused entries, assign categories, and add/remove tags across multi-selection. Category share limits are editable. |
| Torrent context menu and behavior | Present | Preview, open destination, move/rename, category and mixed-state tag assignment, queue controls, recheck/reannounce, tracker details, sequential and first/last priority, automatic management, super seeding, per-torrent options, copy/export, and remove are exposed. |
| Global session and speeds | Present | Pause/resume, normal and alternative speed limits, and completion actions are available. macOS sleep/restart/shutdown actions use a native confirmation and system event; hibernate is unavailable on macOS. |
| General details | Present | The native tab displays qBittorrent's torrent-property fields, hashes, connection counts and limits, rates, totals, share metrics, piece metadata, timing, and the downloaded-piece and availability diagrams. |
| Tracker details | Present | Add, edit, remove, tier changes, move between tiers, and copy are available. Force reannounce is available from the torrent context menu. |
| Peer details | Present | Country flags and names, IP/port, connection, flags, client and peer ID client, progress, rates, totals, relevance, contribution, and active files are displayed; add, ban, and copy actions are available. Country information depends on the backend's country database. |
| HTTP sources | Present | Add, edit, remove, and copy are available. |
| Content details | Present | Name, size, availability, progress, and priority are displayed. Multiple files can be selected for priority changes; rename and media preview are available. |
| Speed details | Present | The session graph includes total, payload, overhead, DHT, and tracker rates in both directions, with per-series toggles and 1-minute through 24-hour ranges. History is sampled while qBitX is running and is not persisted across launches. |
| Search | Present | Search categories and plugins, query history, concurrent result tabs with per-tab stop, name-only/everywhere query filtering, wildcard/regex text filtering, seed-count and size filters, sortable and customizable result columns, batch download and add-options windows, description-page opening, copy links, and plugin install/update/enable/remove are available. Plugin results use the selected engine for metadata preview and add options. Search still requires compatible qBittorrent search plugins. |
| RSS and automatic downloader | Present | Feed/folder management, article actions, rules, enable/disable, rename/clone/remove, matching articles, import/export, category/tags/path, stopped state, layout, and priority options are available. |
| Preferences | Partial | All Web API-exposed backend preferences are searchable across sections and editable with type-aware controls. Booleans use toggles, numeric and text values retain editable fields, and qBittorrent's fixed-choice settings use labeled menus for protocol/encryption, proxy and SMTP types, torrent add behavior, share-limit actions, scheduler days, disk I/O, and peer upload algorithms. Network interface and address menus load their values from the backend when those endpoints are available. Multiline lists and JSON values use scrolling editors. Passwords can be replaced or cleared without displaying the stored value; the API key is masked and can be generated, copied, rotated, or deleted with confirmation. qBittorrent validates saved values. Free-form paths and locale still use text entry instead of the original contextual pickers. |
| Torrent creator | Present | v1/v2/hybrid format, piece size, private mode, source/comment, trackers and web seeds, hidden-file handling, task history, export, and task removal are available. |
| Cookies and plugin management | Present | Cookie editing and search-plugin management are available. |
| Statistics and execution log | Present | qBittorrent session statistics fields and log severity/search filters are available. |
| Menus, toolbar, and window layout | Present | Toolbar visibility and label style, queue controls, filter sidebar, details pane, status bar, speed in title bar, interface lock, About/help links, and session/tools menus are available. Native File, Transfers, Navigate, and Settings commands include macOS keyboard shortcuts for core actions, including adding links from the clipboard. |

## Verification completed

- Swift package debug and release builds targeting macOS 26, plus the C++ backend build.
- Packaged UI smoke test against a fresh `/tmp` backend profile and separate port; the current release executable launched, connected to qBittorrent v5.3.0beta1, and enabled peer-country resolution in that test profile. The profile and backend were isolated from the normal library.
- Isolated Web API checks for RSS rules and folders, categories/tags, per-torrent limits, torrent creation options, metadata preview/file priorities, tracker tiers, session statistics, bulk tag assignment/removal, and multi-file priority changes. These checks used temporary qBittorrent profiles rather than the user's normal profile.
- Isolated qBittorrent v5.3.0beta1 backend check for preference updates, password replacement and clearing, proxy enum values, network interface/address lists, API-key rotation/revocation, and deletion. The throwaway backend profile was terminated after the check.
- Compared the native preference controls with qBittorrent's Web UI preference fields and API getters/setters. Fixed-choice backend preferences now use their qBittorrent labels and serialized values; network interface pickers use the matching API endpoints.
- Older API behavior is guarded in the client: missing tracker summaries decode as empty, unsupported actions show the server's HTTP error, and an unavailable Web API version now produces an explicit compatibility warning.
- `git diff --check`.

## Backend API version support

- Full parity requires Web API 2.16.2 or newer, matching this source tree's `API_VERSION`. The 2.16.2 changelog adds RSS rule import/export and category share-limit fields used by qBitX.
- Torrent metadata preview requires Web API 2.11.9; using a search plugin to preview and add a result requires 2.13.1.
- qBitX reads the connected Web API version and warns when it is below the full-parity floor. Older servers may connect, but individual newer workflows can be unavailable.

## Remaining parity gate

1. Exercise the packaged native app with large lists, multi-selection, active transfers, Search, RSS, and accessibility enabled. The smoke test confirmed launch, connection, and the startup country-resolution preference against an isolated backend.
2. Run the preference controls against bundled and remote backends, including password replacement/clearing and network interface selection. Free-form paths and locale remain text inputs and rely on Web API validation.
3. Exercise graceful degradation against older remote qBittorrent versions, including missing tracker summaries and unsupported API actions.

The source and isolated API checks cover the main transfer, search, RSS, organization, diagnostic, and backend preference workflows. This audit remains open until the packaged macOS UI, accessibility, runtime preference editing, and older-backend compatibility are checked.
