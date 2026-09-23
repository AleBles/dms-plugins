// Hyprland Workspace Swapper — DMS daemon plugin.
// Popup that reassigns the focused workspace to another number. Free numbers are plain, occupied ones
// are dimmed and show what is on them; picking an occupied number swaps the two workspaces.
// The DMS rename dialog stores names as "<id> <name>", so the label is rewritten to follow the new id.
// The key combo comes from the plugin settings and is registered with Hyprland at runtime (see below).
// IPC:  dms ipc call workspace-swapper open | close | toggle | setKeybind "<combo>"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    Item {}

    readonly property int gridMax: 10
    readonly property int stepMs: 90

    property int currentId: 0
    property string currentName: ""
    property int selectedId: 0
    property string errorText: ""
    property var queue: []

    // ---- workspace helpers -------------------------------------------------------------------
    function allWorkspaces() {
        const out = [];
        for (const w of Hyprland.workspaces.values) {
            if (w && w.id > 0)
                out.push(w);
        }
        return out;
    }

    function workspaceAt(id) {
        return allWorkspaces().find(w => w.id === id) || null;
    }

    // Numbers shown as cells: 1..gridMax, plus the current one when it sits above the grid.
    function cellIds() {
        const out = [];
        for (let i = 1; i <= gridMax; i++)
            out.push(i);
        if (currentId > gridMax)
            out.push(currentId);
        return out;
    }

    function freeId() {
        let id = 1000;
        while (workspaceAt(id))
            id++;
        return id;
    }

    // "8 Voxolith" on workspace 8 -> "Voxolith"; a bare "8" -> "" (no custom part).
    function customPart(name, id) {
        const n = (name || "").trim();
        if (n === "" || n === String(id))
            return "";
        const prefix = String(id) + " ";
        return n.startsWith(prefix) ? n.slice(prefix.length) : n;
    }

    function renameCmd(id, part) {
        // Clearing a name leaves it blank rather than falling back to the number, so always set one.
        const label = part === "" ? String(id) : id + " " + part.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        return "hl.dsp.workspace.rename({ workspace = " + id + ", name = \"" + label + "\" })";
    }

    function changeIdCmd(from, to) {
        return "hl.dsp.workspace.change_id({ workspace = " + from + ", id = " + to + " })";
    }

    // ---- popup lifecycle ---------------------------------------------------------------------
    function open() {
        if (!CompositorService.isHyprland)
            return;
        // Names set outside Quickshell (rename dialog, hyprctl) are not always in its cache yet.
        Hyprland.refreshWorkspaces();
        openTimer.restart();
    }

    function showPopup() {
        const ws = Hyprland.focusedWorkspace;
        if (!ws || ws.id <= 0)
            return;
        currentId = ws.id;
        currentName = ws.name || "";
        selectedId = ws.id;
        errorText = "";
        win.visible = true;
        Qt.callLater(() => focusScope.forceActiveFocus());
    }

    Timer {
        id: openTimer
        interval: 120
        onTriggered: root.showPopup()
    }

    function close() {
        win.visible = false;
    }

    function toggle() {
        if (win.visible)
            close();
        else
            open();
    }

    IpcHandler {
        target: "workspace-swapper"
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        function toggle(): void { root.toggle(); }
        // Same as the "Key combo" field in the plugin settings; "" removes the plugin's bind.
        function setKeybind(combo: string): void { root.saveKeybind(combo); }
    }

    // ---- applying the change -----------------------------------------------------------------
    // Hyprland refuses an id that is taken, so a swap goes through a scratch id:
    //   current -> tmp,  target -> current,  tmp -> target.
    function confirm() {
        const from = currentId;
        const to = selectedId;
        if (from <= 0 || to <= 0 || from === to) {
            close();
            return;
        }
        const occupant = workspaceAt(to);
        const myPart = customPart(currentName, from);
        const cmds = [];
        if (!occupant) {
            cmds.push(changeIdCmd(from, to));
            cmds.push(renameCmd(to, myPart));
        } else {
            const theirPart = customPart(occupant.name || "", to);
            const tmp = freeId();
            cmds.push(changeIdCmd(from, tmp));
            cmds.push(changeIdCmd(to, from));
            cmds.push(changeIdCmd(tmp, to));
            cmds.push(renameCmd(to, myPart));
            cmds.push(renameCmd(from, theirPart));
        }
        queue = cmds;
        close();
        runner.restart();
    }

    Timer {
        id: runner
        interval: root.stepMs
        repeat: true
        onTriggered: {
            if (root.queue.length === 0) {
                stop();
                resync.running = true;
                return;
            }
            const next = root.queue[0];
            root.queue = root.queue.slice(1);
            Hyprland.dispatch(next);
        }
    }

    // Hyprland announces a renumber as a "changeworkspaceid" event, which Quickshell does not handle, so
    // its workspace list keeps the workspace under the old number. The bar then shows a ghost entry, and
    // clicking it makes Hyprland create a real, empty workspace with the old number next to the renamed
    // one. Hyprland.refreshWorkspaces() cannot repair that: from QML it only updates entries it already
    // knows and never adds or removes any. The one event that makes Quickshell rebuild its workspace,
    // monitor and window lists from scratch is "configreloaded", so a config-only reload (no monitor
    // reset) is issued once the queue has drained.
    Process {
        id: resync
        command: ["hyprctl", "reload", "config-only"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("[workspaceSwapper] hyprctl reload config-only exited with " + exitCode);
        }
    }

    // ---- keybind -------------------------------------------------------------------------------
    // The combo is a plugin setting ("keybind"). It is registered through Hyprland's Lua API with
    // `hyprctl eval`, so no config file is written: the DMS keybind store rewrites binds-user.lua and drops
    // everything in it that is not a bind line. Runtime binds do not survive a config reload, including the
    // config-only reload this plugin issues after a renumber, so "configreloaded" puts the bind back.
    readonly property string toggleCommand: "dms ipc call workspace-swapper toggle"
    property string keybind: ""          // wanted, normalised ("" = the user binds the command themselves)
    property string appliedKeybind: ""   // what Hyprland currently holds for us
    property bool bindPending: false

    // "ctrl+shift+i" -> "CTRL + SHIFT + I" is not attempted: Hyprland key names are case-sensitive, so only
    // the spacing around "+" is normalised.
    function normalizeCombo(combo) {
        return String(combo || "").split("+").map(p => p.trim()).filter(p => p !== "").join(" + ");
    }

    function luaString(value) {
        return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
    }

    function loadSettings() {
        if (!pluginService)
            return;
        keybind = normalizeCombo(pluginService.loadPluginData(pluginId, "keybind", ""));
        applyKeybind();
    }

    function saveKeybind(combo) {
        if (!pluginService)
            return;
        pluginService.savePluginData(pluginId, "keybind", normalizeCombo(combo));
    }

    function applyKeybind() {
        if (!CompositorService.isHyprland || keybind === appliedKeybind)
            return;
        if (binder.running) {
            bindPending = true;
            return;
        }
        const lua = [];
        if (appliedKeybind !== "")
            lua.push("hl.unbind(" + luaString(appliedKeybind) + ")");
        if (keybind !== "")
            lua.push("hl.bind(" + luaString(keybind) + ", hl.dsp.exec_cmd(" + luaString(toggleCommand) + "), { description = " + luaString(I18n.trFor("workspaceSwapper", "Renumber this workspace")) + " })");
        binder.wanted = keybind;
        binder.command = ["hyprctl", "eval", lua.join("; ")];
        binder.running = true;
    }

    Component.onCompleted: loadSettings()
    onPluginServiceChanged: loadSettings()

    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null
        function onPluginDataChanged(id) {
            if (id === root.pluginId)
                root.loadSettings();
        }
    }

    Connections {
        target: Hyprland
        enabled: CompositorService.isHyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded")
                return;
            root.appliedKeybind = "";
            root.applyKeybind();
        }
    }

    Process {
        id: binder
        property string wanted: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            const output = (stdout.text + stderr.text).trim();
            if (exitCode === 0) {
                root.appliedKeybind = wanted;
            } else {
                // The unbind runs first, so whatever we had is gone either way.
                root.appliedKeybind = "";
                console.warn("[workspaceSwapper] could not bind " + wanted + ": " + output);
                ToastService.showWarning(I18n.trFor("workspaceSwapper", "Hyprland Workspace Swapper: could not bind %1").arg(wanted), output.replace(/^error: .*?:\d+: /, ""));
            }
            if (root.bindPending) {
                root.bindPending = false;
                root.applyKeybind();
            }
        }
    }

    // Unloading (disable, reload) takes the bind with it instead of leaving a key that calls into nothing.
    Component.onDestruction: {
        if (appliedKeybind !== "")
            Quickshell.execDetached(["hyprctl", "eval", "hl.unbind(" + luaString(appliedKeybind) + ")"]);
    }

    // ---- popup ---------------------------------------------------------------------------------
    DankFloatingWindow {
        id: win

        objectName: "workspaceSwapperModal"
        title: I18n.trFor("workspaceSwapper", "Renumber Workspace")
        implicitWidth: 460
        implicitHeight: 300
        minimumSize: Qt.size(460, 300)
        maximumSize: Qt.size(460, 300)
        visible: false

        onClosed: root.close()

        FocusScope {
            id: focusScope
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: event => {
                root.close();
                event.accepted = true;
            }
            Keys.onReturnPressed: event => {
                root.confirm();
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                root.confirm();
                event.accepted = true;
            }
            Keys.onLeftPressed: event => {
                root.step(-1);
                event.accepted = true;
            }
            Keys.onRightPressed: event => {
                root.step(1);
                event.accepted = true;
            }
            Keys.onUpPressed: event => {
                root.step(-5);
                event.accepted = true;
            }
            Keys.onDownPressed: event => {
                root.step(5);
                event.accepted = true;
            }
            Keys.onPressed: event => {
                // 1..9 pick directly, 0 picks 10.
                if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                    const digit = event.key - Qt.Key_0;
                    root.selectedId = digit === 0 ? 10 : digit;
                    event.accepted = true;
                }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - Theme.spacingL * 2
                spacing: Theme.spacingM

                StyledText {
                    width: parent.width
                    text: {
                        const part = root.customPart(root.currentName, root.currentId);
                        const label = part === "" ? String(root.currentId) : root.currentId + " " + part;
                        return I18n.trFor("workspaceSwapper", "Move workspace %1 to another number").arg(label);
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                }

                Grid {
                    id: grid
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 5
                    spacing: Theme.spacingS

                    Repeater {
                        model: root.cellIds()

                        Rectangle {
                            required property int modelData

                            readonly property var occupant: root.workspaceAt(modelData)
                            readonly property bool isCurrent: modelData === root.currentId
                            readonly property bool isSelected: modelData === root.selectedId
                            readonly property bool isTaken: occupant !== null && !isCurrent

                            width: 78
                            height: 64
                            radius: Theme.cornerRadius
                            color: isSelected ? Theme.primaryContainer : (isTaken ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
                            border.width: isCurrent ? 2 : 1
                            border.color: isCurrent ? Theme.primary : (isSelected ? Theme.primary : Theme.outlineMedium)
                            opacity: isTaken && !isSelected ? 0.75 : 1

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: String(modelData)
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 70
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    text: {
                                        if (isCurrent)
                                            return I18n.trFor("workspaceSwapper", "this one");
                                        if (!occupant)
                                            return I18n.trFor("workspaceSwapper", "free");
                                        const part = root.customPart(occupant.name || "", modelData);
                                        return part === "" ? I18n.trFor("workspaceSwapper", "in use") : part;
                                    }
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    color: Theme.surfaceVariantText
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.selectedId = modelData;
                                    root.confirm();
                                }
                            }
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        if (root.selectedId === root.currentId)
                            return I18n.trFor("workspaceSwapper", "Pick a number · Enter confirms · Esc cancels");
                        const occupant = root.workspaceAt(root.selectedId);
                        if (occupant)
                            return I18n.trFor("workspaceSwapper", "%1 is in use — the two workspaces swap places").arg(root.selectedId);
                        return I18n.trFor("workspaceSwapper", "Move to %1").arg(root.selectedId);
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // Arrow-key movement across the grid, clamped to the cells on show.
    function step(delta) {
        const ids = cellIds();
        let idx = ids.indexOf(selectedId);
        if (idx < 0)
            idx = 0;
        idx = Math.max(0, Math.min(ids.length - 1, idx + delta));
        selectedId = ids[idx];
    }
}
