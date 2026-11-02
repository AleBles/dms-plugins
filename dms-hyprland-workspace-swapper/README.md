# Hyprland Workspace Swapper

A [Dux Shell](https://github.com/duxlabs-dev/dux-shell) plugin that gives the current
workspace a different number. Free numbers are taken straight away; picking a number that is already
in use swaps the two workspaces, so nothing ever becomes unreachable.

<p align="center">
  <img src="assets/screenshot.png" alt="Hyprland Workspace Swapper popup" width="520"/>
</p>

## Features

- Grid of numbers 1 to 10, plus the current workspace when it sits above the grid
- Each cell shows what is on that number: free, in use, or the workspace's name
- Pick with a digit key, the arrow keys, or a click; Enter confirms, Escape cancels
- Occupied numbers swap the two workspaces instead of refusing
- Workspace names follow the new number, so `8 Voxolith` becomes `3 Voxolith`
- Key combo set from the DMS settings UI; the plugin registers it with Hyprland itself

## Requirements

- Dux Shell (DMS) >= 2.0.0
- Hyprland. The renumbering uses Hyprland's `change_id` dispatcher, which other compositors do not have.

## Install

```sh
git clone https://github.com/AleBles/dms-plugins
ln -s "$PWD/dms-plugins/dms-hyprland-workspace-swapper" ~/.config/dms/plugins/hyprland-workspace-swapper
dms restart
```

Then enable it in **DMS Settings → Plugins → Hyprland Workspace Swapper**, or run
`dms ipc call plugins enable workspaceSwapper`, and pick a key combo on the same settings page.

## Usage

Set a key combo in **DMS Settings → Plugins → Hyprland Workspace Swapper**, in Hyprland's key syntax, for example
`SUPER + CTRL + SHIFT + I` (avoid `CTRL + SHIFT + I`: browsers use it for developer tools). The plugin registers the bind with Hyprland at runtime through `hyprctl eval` and puts it
back after every config reload, so nothing is written to your Hyprland config. Disabling the plugin removes
the bind again.

If you would rather keep the bind in your own config, leave the field empty and bind the command yourself,
for example in a Hyprland Lua config:

```lua
hl.bind("SUPER + CTRL + SHIFT + I", hl.dsp.exec_cmd("dms ipc call workspace-swapper toggle"),
        { description = "Renumber this workspace" })
```

Do not do both: `hl.bind` stacks, so one press would open and close the popup.

IPC: `dms ipc call workspace-swapper open | close | toggle | setKeybind "<combo>"`. `setKeybind` changes the
same setting as the UI field; an empty string removes the plugin's bind.

## Notes

The DMS rename dialog stores workspace names as `<id> <name>`. This plugin rewrites that prefix after
a move so the label keeps matching the number. Hyprland's own rename leaves a name blank when cleared,
so the plugin always writes an explicit name.

After a move the plugin runs `hyprctl reload config-only`. Hyprland reports a renumber with a
`changeworkspaceid` event that Quickshell does not handle, so without the reload the bar keeps showing
the workspace under its old number, and clicking that ghost creates a real empty workspace there. The
reload is the only way to make Quickshell rebuild its workspace list; `config-only` skips the monitor
reset, and Hyprland startup commands registered through `hl.on("hyprland.start", ...)` do not run
again.

## License

[MIT](LICENSE)
