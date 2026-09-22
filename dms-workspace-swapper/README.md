# Workspace Swapper

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) plugin that gives the current
workspace a different number. Free numbers are taken straight away; picking a number that is already
in use swaps the two workspaces, so nothing ever becomes unreachable.

<p align="center">
  <img src="assets/screenshot.png" alt="Workspace Swapper popup" width="520"/>
</p>

## Features

- Grid of numbers 1 to 10, plus the current workspace when it sits above the grid
- Each cell shows what is on that number: free, in use, or the workspace's name
- Pick with a digit key, the arrow keys, or a click; Enter confirms, Escape cancels
- Occupied numbers swap the two workspaces instead of refusing
- Workspace names follow the new number, so `8 Voxolith` becomes `3 Voxolith`

## Requirements

- DankMaterialShell >= 1.6.0
- Hyprland. The renumbering uses Hyprland's `change_id` dispatcher, which other compositors do not have.

## Install

```sh
git clone https://github.com/AleBles/dms-plugins
ln -s "$PWD/dms-plugins/dms-workspace-swapper" ~/.config/DankMaterialShell/plugins/workspace-swapper
dms restart
```

Then enable it in **DMS Settings → Plugins → Workspace Swapper**, or run
`dms ipc call plugins enable workspaceSwapper`.

## Usage

Bind the popup to a key, for example in a Hyprland Lua config:

```lua
hl.bind("CTRL + SHIFT + I", hl.dsp.exec_cmd("dms ipc call workspace-swapper toggle"),
        { description = "Renumber this workspace" })
```

IPC: `dms ipc call workspace-swapper open | close | toggle`.

## Notes

The DMS rename dialog stores workspace names as `<id> <name>`. This plugin rewrites that prefix after
a move so the label keeps matching the number. Hyprland's own rename leaves a name blank when cleared,
so the plugin always writes an explicit name.

## License

[MIT](LICENSE)
