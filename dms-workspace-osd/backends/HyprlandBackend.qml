// Hyprland: the `workspacev2` raw event ("ID,NAME"); windows from Hyprland.toplevels.
import QtQuick
import Quickshell.Hyprland
import qs.Services

WorkspaceBackend {
    id: backend
    name: "hyprland"
    available: CompositorService.isHyprland

    Connections {
        target: Hyprland
        enabled: backend.available
        function onRawEvent(event) {
            if (event.name !== "workspacev2") return;
            const parts = event.parse(2);
            const id = parseInt(parts[0]);
            if (isNaN(id) || id < 0) return;                   // special workspaces have negative ids
            let mon = "";
            const ws = Array.from(Hyprland.workspaces?.values || []).find(w => w.id === id);
            if (ws && ws.monitor) mon = ws.monitor.name;
            else if (Hyprland.focusedMonitor) mon = Hyprland.focusedMonitor.name;
            backend.workspaceActivated({ key: "hyprland:" + id, number: id, name: parts[1] || "", output: mon });
        }
    }

    function listWindows(ws, done) {
        const entries = [];
        for (const t of Array.from(Hyprland.toplevels?.values || [])) {
            if (!t.workspace || t.workspace.id !== ws.number) continue;
            entries.push({ appId: t.wayland?.appId || t.lastIpcObject?.class || "", title: t.title || "" });
        }
        done(entries);
    }
}
