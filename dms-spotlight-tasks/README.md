# Spotlight Tasks

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) launcher plugin for [Dagr](https://github.com/alebles/dagr): type `+` in the launcher to search your open tasks, add a new one from whatever you typed, and press Enter on a task to mark it done.

<p align="center">
  <img src="assets/screenshot.png" alt="Spotlight Tasks in the DMS launcher" width="600"/>
</p>

## Features

- Add a task without leaving the launcher — anything you type is offered as **Add task**, so it works even when nothing matches
- Search your open tasks by title or priority; Enter marks one done
- Priority marks still apply: `+ !! pay rent` adds "pay rent" two levels above the default, because the text reaches Dagr untouched
- Right-click (or Tab) a task to delete it
- Live: the list updates when you change something in the Dagr window, without reopening the launcher
- One keybind opens the launcher pre-filled: `dms ipc call spotlight toggleQuery "+ "`
- Add from anywhere, no launcher at all: `dms ipc call tasks add "buy bread"`
- Never touches the database — everything goes through Dagr's service
- Configurable from the DMS settings UI: trigger, how many tasks, toasts, socket path
- Translatable; ships with Dutch

## Requirements

- DankMaterialShell >= 1.6.0
- [Dagr](https://github.com/alebles/dagr). It is not on Flathub or in any distro
  repository — build it from source, or download the `dagr.flatpak` bundle
  attached to the [latest release](https://github.com/alebles/dagr/releases/latest).
- Dagr's background service, running. Let Dagr tell you how to set it up, since
  a Flatpak install puts no `dagr` command on your PATH and the steps differ:

  ```sh
  dagr setup                              # native build
  flatpak run dev.ables.Dagr setup        # Flatpak
  ```

  Once it is up, `dagr status` should print a socket path and a database.

The plugin talks to that service over `$XDG_RUNTIME_DIR/dagr/dagr.sock`. It does not care how Dagr was installed, and it never opens the database itself. If the service is not running, the launcher shows a single row saying so — rather than blocking the plugin from being enabled, since the service may legitimately start a moment later.

Any compositor: this plugin does not touch the window manager.

## Install

### From the plugin registry

DMS Settings (`Mod + ,`) → **Plugins** → **Browse** → *Spotlight Tasks*, or:

```sh
dms plugins install spotlightTasks
```

### Manual

```sh
git clone https://github.com/AleBles/dms-spotlight-tasks \
  ~/.config/DankMaterialShell/plugins/spotlight-tasks
dms ipc call plugin-scan scan
dms ipc call plugins enable spotlightTasks
```

## Usage

| | |
|---|---|
| `+` | list your open tasks |
| `+ rent` | tasks matching "rent", plus **Add task: rent** |
| `+ !! pay rent` | add "pay rent" two priority levels above the default |
| Enter on a task | mark it done |
| Tab / right-click | delete it |

Handy keybinds:

```sh
dms ipc call spotlight toggleQuery "+ "     # open the launcher ready to type
dms ipc call tasks add "buy bread"          # add with no UI at all
dms ipc call tasks status                   # online, and how many are open
```

## How it is put together

Two surfaces, and the split matters:

- **`SpotlightTasksDaemon.qml`** holds the socket. It subscribes to Dagr's change notifications, keeps a cache of the open task list in plugin global variables, and owns the `tasks` IPC target. It is a `daemon` surface because those are instantiated once, at shell start.
- **`SpotlightTasks.qml`** reads that cache and nothing else. `getItems` is called synchronously on every keystroke, so it must never do I/O.

Putting the socket in the launcher surface would look simpler and would be wrong: launcher surfaces are only created the first time someone opens the launcher, so the first search would come up empty.

The two surfaces are separate objects, so commands travel the other way through a shared `cmd` variable with a sequence number — the launcher cannot reach the daemon's socket directly.

Matching and ranking happen in the plugin via `_preScored`, which the launcher's scorer uses verbatim: **Add task** is pinned to the top, then tasks in Dagr's own display order.

## The protocol

Dagr's socket speaks one JSON object per line, which is exactly what Quickshell's `SplitParser` reads:

```jsonc
{"event":"hello","protocol":1,"version":"0.2.0","db":"/home/…/dagr.db"}
{"id":1,"method":"list_tasks","params":{"include_done":false}}
{"id":1,"ok":true,"result":{"version":1235,"tasks":[…],"priorities":[…],"settings":{…}}}
{"event":"changed","version":1236}
```

Two things the plugin has to respect:

- `protocol` is checked on connect; an unknown number logs a warning rather than misreading the stream.
- A task's `priority` is **absent entirely** when priorities are switched off in Dagr. Reading `task.priority.name` unguarded would crash the launcher.

## Development

```sh
dms ipc call plugin-scan reload spotlightTasks   # picks up edited QML
bun scripts/registry.ts --check                  # registry entry up to date?
```

`dms ipc call plugins reload` is *not* enough on its own — it serves a cached copy of the QML. Use `plugin-scan reload <id>`.

Shell logs, QML errors included, are in `$XDG_RUNTIME_DIR/quickshell/by-id/*/log.log`.

To work against a development build of Dagr, start it with its own socket and point the plugin at it in the settings:

```sh
DAGR_SOCKET=$XDG_RUNTIME_DIR/dagr/dev.sock cargo run -- serve
```

## License

MIT
