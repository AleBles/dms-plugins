# Changelog

All notable changes to Workspace OSD Flash are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-09-17

### Added
- Pluggable compositor backends in `backends/`: one small file per compositor behind a shared
  `WorkspaceBackend` contract (`workspaceActivated(ws)` + `listWindows(ws, done)`). The daemon loads
  exactly one, chosen by `CompositorService.compositor`.
- Mango (mangowc) support: the active tag per output is shown as the workspace, clients as windows.
- sway, scroll and Miracle WM support through the i3 IPC (`Quickshell.I3`); window lists via
  `swaymsg -t get_tree` (`scrollmsg` on scroll) when the tool is installed.
- labwc and any other ext-workspace-v1 compositor through `Quickshell.WindowManager` (no window list:
  the protocol has no window mapping).
- Startup check (`StartupCheck.qml`): refuses to enable on compositors no backend can serve and
  explains why in a toast.
- Dutch translation (`translations/nl.json`) covering every string, including the card labels.
- One log line per flash (`[WorkspaceOsdFlash] flash "Workspace 2" on DP-1 - 3 windows`), used by the
  testbed scripts and handy for support.
- `package.json` scripts driving [dms-testbed](https://github.com/AleBles/dms-testbed) for all six
  compositors (`test:<comp>`, `test:all`, `test:switch`, `test:logs`, `test:shot`, `test:start`,
  `test:restart-shell`, `test:stop`).
- `$schema`, `category`, `dependencies` and the `ipc` capability in `plugin.json`.

### Changed
- Plugin id and name are `workspaceOsdFlash` / "Workspace OSD Flash" everywhere (settings page,
  translation calls, README, registry entry). Previously the settings page still wrote to `workspaceOsd`,
  so changes made in the DMS settings UI never reached the daemon.
- `requires_dms` is `>=1.6.0`: the plugin uses `I18n.trFor`, which DMS added in 1.6.0.
- Card label and "+N more" text are translatable (`Workspace %1: %2`, `Workspace %1`, `+%1 more`).
- Label and window-line formatting moved to `Labels.js` (pure functions).
- The Hyprland `flash()` helper is `showFlash()` internally; the IPC surface (`wsosd flash|hide`) is unchanged.
- README rewritten: per-compositor support table, install/update/uninstall by registry id, IPC
  argument rules, translations and testing sections.

### Fixed
- niri workspace numbers were off by one (`idx + 1`); the card now shows the same number as the DMS bar.
- A newly connected output no longer triggers a flash on niri.
- DMS's own toplevels (`com.danklinux.dms`, `org.quickshell`) are no longer listed as windows.
- IPC documentation: all three `flash` arguments are required (Quickshell rejects fewer), pass `""` to skip one.

### Notes
- After updating an installed copy, run `dms restart` once: `dms ipc call plugins reload` reuses Qt's
  cached directory listing, and files that did not exist when the shell started fail with
  `File name case mismatch`.

## [0.1.0] - 2026-09-07

### Added
- Initial release: centered workspace card on Hyprland and niri with hold/fade timing, DMS theming,
  window list under the label, label styles, position setting and the `wsosd` IPC target.

[0.2.0]: https://github.com/AleBles/dms-workspace-osd/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/AleBles/dms-workspace-osd/releases/tag/v0.1.0
