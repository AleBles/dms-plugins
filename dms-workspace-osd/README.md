# Workspace OSD Flash

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) daemon plugin that briefly shows the id and name of the workspace you just switched to, centered on that screen.

<p align="center">
  <img src="assets/screenshot.png" alt="Workspace OSD card" width="600"/>
</p>

## Features

- Centered card with the workspace number and, if it has one, its name
- Small list underneath with the windows open on that workspace, one per line as `App · Window title` (or grouped app names), folding the rest into `+N more`
- Shown on the screen whose workspace changed, so it works per monitor
- Quick switching never queues: a new switch replaces the text immediately
- Fades and shrinks out after a configurable hold time
- Click-through overlay, never steals focus or input
- Styled like DMS's own OSDs: theme colours, corner radius, popup transparency, elevation shadow, blur and blur border, font family and size, animation speed, light/dark mode
- Configurable from the DMS settings UI: hold time, fade duration, text size, name on/off, label style, position
- One small backend file per compositor; every compositor DMS documents is covered
- Translatable; ships with Dutch

## Requirements

- DankMaterialShell >= 1.6.0 (uses the plugin translation API introduced in 1.6.0)
- One of the compositors below. A startup check refuses to enable the plugin anywhere else and shows the reason as a toast.

| Compositor | Switch detection | Window list | Status |
|---|---|---|---|
| Hyprland | `workspacev2` event | yes | tested |
| niri | DMS niri service | yes | tested in the testbed |
| Mango (mangowc) | DMS Mango service, tags shown as workspaces | yes | tested in the testbed |
| sway | i3 IPC `workspace` event | yes, needs `swaymsg` | tested in the testbed |
| Miracle WM | i3 IPC `workspace` event | yes, needs `swaymsg` | tested in the testbed (headless Mir) |
| labwc | ext-workspace-v1 | no (the protocol has no window mapping) | tested in the testbed |
| scroll | i3 IPC, same backend as sway | yes, needs `scrollmsg` | untested |
| anything else with ext-workspace-v1 | ext-workspace-v1 | no | untested |

"Tested in the testbed" means the nested containers of [dms-testbed](https://github.com/AleBles/dms-testbed); the author runs Hyprland.

## Install

### From the plugin registry

DMS Settings (`Mod + ,`) → **Plugins** → **Browse** → *Workspace OSD Flash*, or:

```sh
dms plugins install workspaceOsdFlash
```

Update later with `dms plugins update workspaceOsdFlash`; remove with `dms plugins uninstall workspaceOsdFlash`.

### Manual

```sh
git clone https://github.com/AleBles/dms-workspace-osd \
  ~/.config/DankMaterialShell/plugins/workspace-osd-flash
dms restart
```

Then enable it in **DMS Settings → Plugins → Workspace OSD Flash**, or run `dms ipc call plugins enable workspaceOsdFlash`.

After an update that adds new files to the plugin, run `dms restart` once. `dms ipc call plugins reload` reuses Qt's cached directory listing, and a file that was not there when the shell started fails with `File name case mismatch` in the DMS log.

## Settings

| Setting | Default | Notes |
|---|---|---|
| Hold time | 700 ms | Time before the fade-out starts |
| Fade-out duration | follows DMS | Set a value in ms to override the DMS animation speed |
| Accent border | on | Thin primary-coloured ring on top of the DMS surface |
| Text size | 44 px | The card scales with the text |
| Show workspace name | on | Include the name when the workspace has one |
| List open windows | on | One small line per window under the label |
| App lines show | Window titles | `App · Title`, or app names grouped with a count |
| App lines alignment | Left | Left-aligned block under the label, or centered lines |
| Max characters per line | 100 | Longer lines are cut with an ellipsis, 0 disables |
| Max lines | 6 | Further windows fold into `+N more` |
| Label style | `Workspace 2: work` | Also `2 · work` and name-only |
| Position | center | Center, top or bottom of the screen |

## Naming workspaces

On Hyprland the DMS rename dialog (`Ctrl + Shift + R` by default) stores the name as `<id> <name>`. The plugin strips the duplicated id, so a workspace renamed to `work` shows as **Workspace 2: work**.

On niri the number shown is the workspace's index on its output, the same number the DMS bar shows. On Mango the active tag is the number. On sway a workspace that only has a name shows just the name. On labwc the desktop names from `rc.xml` are the names.

## How it is put together

```
WorkspaceOsd.qml               daemon: settings, flash state, the card, IPC; loads one backend
Labels.js                      label and window-line formatting (pure functions)
backends/WorkspaceBackend.qml  the contract: `workspaceActivated(ws)` + `listWindows(ws, done)`
backends/HyprlandBackend.qml   NiriBackend.qml  MangoBackend.qml  SwayBackend.qml  ExtWorkspaceBackend.qml
StartupCheck.qml               refuses unsupported compositors
```

The daemon maps `CompositorService.compositor` to a backend file (`hyprland`, `niri`, `mango`, and `sway`/`scroll`/`miracle` to the sway backend); anything else gets the ext-workspace backend. To add a compositor, drop a `backends/<Name>Backend.qml` that derives from `WorkspaceBackend` and add one entry to `backendFor` in `WorkspaceOsd.qml`.

## IPC

Other tools can flash a message on a screen. Quickshell IPC requires every argument, so pass `""` for the ones you do not need:

```sh
dms ipc call wsosd flash "Hello" "DP-1" "line one | line two"   # text, monitor ("" = all screens), lines ("" = none)
dms ipc call wsosd flash "Hello" "" ""
dms ipc call wsosd hide
```

Every flash is logged as `[WorkspaceOsdFlash] flash "Workspace 2" on DP-1 - 3 windows` in the DMS log.

## Testing

[dms-testbed](https://github.com/AleBles/dms-testbed) runs DMS in nested containers for all six compositors. With `npm install` (or `bun install`) done once in this repo:

```sh
npm run test:sway          # start a nested sway with this plugin and switch to workspace 2
npm run test:all           # all six, one after the other
npm run test:start         # bring stopped containers back, same mounts, no recreate
npm run test:switch        # switch every running container to workspace 3
npm run test:restart-shell # restart DMS inside each container (after adding plugin files)
npm run test:logs          # the plugin's flash lines from every container's DMS log
npm run test:shot          # screenshots/<compositor>.png right after a switch
npm run test:stop
```

## Translations

The plugin ships Dutch (`translations/nl.json`); the English strings in the QML files are the source. DMS picks the file matching the shell locale automatically.

To add a language, create `translations/<locale>.json` (`de.json`, `zh_CN.json`, ...) with one bucket per English term:

```json
{
  "Hold time": { "Hold time": "Anzeigedauer" }
}
```

Untranslated terms fall back to English. Reload with `dms ipc call plugins reload workspaceOsdFlash` and switch the language under **DMS Settings → Locale** to check. Pull requests with new languages are welcome.

## License

[MIT](LICENSE)
