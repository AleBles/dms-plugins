// Mango (mangowc): diff of the active tags per output in MangoService.outputs; tags are shown as
// workspaces. Clients in MangoService.windows carry 1-based tag numbers and their monitor name.
import QtQuick
import qs.Services

WorkspaceBackend {
    id: backend
    name: "mango"
    available: CompositorService.isMango && MangoService.available

    property var _active: ({})        // output -> "1,2" (sorted active tags)
    property bool _primed: false

    Connections {
        target: MangoService
        enabled: backend.available
        function onStateChanged() {
            const outputs = MangoService.outputs || {};
            const next = {};
            for (const name in outputs) {
                // activeTags is 1-based; 0 (or an empty list) means the overview is open.
                const tags = (outputs[name].activeTags || []).filter(t => t > 0).sort((a, b) => a - b);
                if (tags.length > 0) next[name] = tags;
            }
            if (backend._primed) {
                for (const name in next) {
                    const tags = next[name];
                    const prev = backend._active[name];
                    // Only a change on an output we already knew about; leaving the overview back to
                    // the same tag is not a switch either.
                    if (prev !== undefined && prev !== tags.join(","))
                        backend.workspaceActivated({ key: "mango:" + name + ":" + tags.join(","), number: tags[0], name: "", output: name, tags: tags });
                }
            }
            const snapshot = {};
            for (const name in next) snapshot[name] = next[name].join(",");
            for (const name in backend._active)
                if (!(name in snapshot)) snapshot[name] = backend._active[name];   // keep through the overview
            backend._active = snapshot;
            backend._primed = true;
        }
    }

    function listWindows(ws, done) {
        const entries = [];
        for (const c of (MangoService.windows || [])) {
            if (!c || c.monitor !== ws.output || c.is_minimized) continue;
            if (!(c.tags || []).some(t => ws.tags.indexOf(t) >= 0)) continue;
            entries.push({ appId: c.appid || "", title: c.title || "" });
        }
        done(entries);
    }
}
