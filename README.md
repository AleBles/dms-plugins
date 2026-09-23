# dms-plugins

Plugins for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell), kept in one
repository. Each directory is a self-contained plugin: DMS reads its `plugin.json` and QML directly,
so a plugin works whether it is used from here or copied out on its own.

| Plugin | Id | What it does |
| --- | --- | --- |
| [dms-workspace-osd](dms-workspace-osd) | `workspaceOsdFlash` | Flashes the id and name of the workspace you switched to, centered on that screen |
| [dms-hyprland-workspace-swapper](dms-hyprland-workspace-swapper) | `workspaceSwapper` | Popup that renumbers the current workspace, swapping with whatever holds that number |
| [dms-spotlight-tasks](dms-spotlight-tasks) | `spotlightTasks` | Add and complete Dagr tasks from the DMS launcher |
| [dms-widget-openvpn3](dms-widget-openvpn3) | `openvpn3` | Bar widget for the openvpn3-linux client |

## Install one plugin

DMS loads anything under `~/.config/DankMaterialShell/plugins/`, so a symlink is enough:

```sh
git clone https://github.com/AleBles/dms-plugins
ln -s "$PWD/dms-plugins/dms-hyprland-workspace-swapper" ~/.config/DankMaterialShell/plugins/hyprland-workspace-swapper
dms restart
dms ipc call plugins enable workspaceSwapper
```

`dms restart` is needed only when a plugin directory appears or disappears. After editing files in
place, `dms ipc call plugin-scan reload <id>` is usually enough, though QML can be served from cache,
so restart before trusting a test.

## Working on a plugin

Each plugin carries its own `package.json` with bun scripts:

```sh
cd dms-hyprland-workspace-swapper
bun run registry          # regenerate registry/<owner>-<plugin>.json from plugin.json
bun run registry:check    # fail if that file is missing or stale
bun run reload            # ask DMS to reload just this plugin
```

## Registry entries

Every plugin keeps its submission for the
[DMS plugin registry](https://github.com/AvengeMedia/dms-plugin-registry) in `registry/`, generated
from `plugin.json` by `scripts/registry.ts`. Because these plugins live in a monorepo, each entry
carries a `path` pointing at its directory, and the screenshot URL includes that path. To submit one,
copy its `registry/*.json` into a fork of the registry under `plugins/` and open a pull request.

## License

[MIT](LICENSE)
