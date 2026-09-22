// Any compositor with ext-workspace-v1 (labwc, ...), through Quickshell.WindowManager: a windowset
// turning `active` is a switch. The protocol carries no window-to-workspace mapping, so no lines.
import QtQuick
import Quickshell
import Quickshell.WindowManager

WorkspaceBackend {
    id: backend
    name: "ext-workspace"
    available: (WindowManager.windowsets?.length ?? 0) > 0

    Instantiator {
        model: WindowManager.windowsets
        delegate: Connections {
            target: modelData
            function onActiveChanged() {
                if (modelData.active) backend._activated(modelData);
            }
        }
    }

    function _activated(set) {
        const where = backend._locate(set);
        const name = set.name || "";
        backend.workspaceActivated({
            key: "ext:" + (set.id || name),
            number: where.number,
            name: name === String(where.number) ? "" : name,
            output: where.output
        });
    }

    // Screen showing this windowset and its 1-based position there (ext-workspace coordinates when given).
    function _locate(set) {
        for (const screen of Quickshell.screens) {
            const proj = WindowManager.screenProjection(screen);
            const list = Array.from(proj?.windowsets || []).filter(w => w.shouldDisplay);
            const idx = list.findIndex(w => w === set || (set.id && w.id === set.id));
            if (idx < 0) continue;
            const coords = set.coordinates;
            const number = (coords && coords.length > 0) ? coords[0] + 1 : idx + 1;
            return { output: screen.name, number: number };
        }
        return { output: "", number: -1 };
    }
}
