// niri: diff of the active workspace per output in NiriService.allWorkspaces; windows from
// NiriService.windows. niri's `idx` is 1-based and is the number DMS shows in its bar.
import QtQuick
import qs.Services

WorkspaceBackend {
    id: backend
    name: "niri"
    available: CompositorService.isNiri

    property var _active: ({})        // output -> workspace id
    property bool _primed: false

    Connections {
        target: NiriService
        enabled: backend.available
        function onAllWorkspacesChanged() {
            const next = {};
            for (const ws of (NiriService.allWorkspaces || []))
                if (ws.is_active && ws.output) next[ws.output] = ws;
            if (backend._primed) {
                for (const out in next) {
                    const ws = next[out];
                    // Only a change on an output we already knew about; a newly appearing output is not a switch.
                    if (backend._active[out] !== undefined && backend._active[out] !== ws.id)
                        backend.workspaceActivated({ key: "niri:" + ws.id, number: ws.idx, name: ws.name || "", output: out, wsId: ws.id });
                }
            }
            const snapshot = {};
            for (const out in next) snapshot[out] = next[out].id;
            backend._active = snapshot;
            backend._primed = true;
        }
    }

    function listWindows(ws, done) {
        const entries = [];
        for (const w of (NiriService.windows || []))
            if (w.workspace_id === ws.wsId) entries.push({ appId: w.app_id || "", title: w.title || "" });
        done(entries);
    }
}
