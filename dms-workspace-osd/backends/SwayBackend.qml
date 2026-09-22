// sway, scroll and Miracle WM (all speak the i3 IPC that Quickshell.I3 wraps): the "workspace"
// event with change "focus". Quickshell exposes no window tree, so the window list comes from
// `swaymsg -t get_tree` (`scrollmsg` on scroll); when the tool is missing the card shows no lines.
import QtQuick
import Quickshell.Io
import Quickshell.I3
import qs.Services

WorkspaceBackend {
    id: backend
    name: CompositorService.isScroll ? "scroll" : (CompositorService.isMiracle ? "miracle" : "sway")
    available: CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle

    Connections {
        target: I3
        enabled: backend.available
        function onRawEvent(event) {
            if (event.type !== "workspace") return;
            let d = null;
            try { d = JSON.parse(String(event.data || "")); } catch (e) { return; }
            if (!d || d.change !== "focus" || !d.current) return;
            const cur = d.current;
            const num = (typeof cur.num === "number" && cur.num >= 0) ? cur.num : -1;
            backend.workspaceActivated({ key: "i3:" + (cur.id ?? cur.name), number: num, name: cur.name || "", output: cur.output || "" });
        }
    }

    // ---- window list ---------------------------------------------------------------------
    // One get_tree at a time. A switch that arrives while a query runs replaces the pending request;
    // the running query's result is then dropped and the tree is fetched again for the new workspace.
    property var _pending: null          // { ws, done } waiting for a tree
    property string _runningKey: ""      // ws.key the running process was started for

    Process {
        id: tree
        command: [CompositorService.isScroll ? "scrollmsg" : "swaymsg", "-t", "get_tree"]
        stdout: StdioCollector {
            onStreamFinished: backend._deliver(text)
        }
        onRunningChanged: if (!running) failTimer.restart()     // covers "binary not found": no stream ever finishes
    }
    Timer {
        id: failTimer
        interval: 300
        onTriggered: if (!tree.running) backend._deliver("")   // a new query may have started meanwhile
    }

    function listWindows(ws, done) {
        backend._pending = { ws: ws, done: done };
        if (!tree.running) backend._start();
    }

    function _start() {
        failTimer.stop();
        backend._runningKey = backend._pending.ws.key;
        tree.running = true;
    }

    function _deliver(text) {
        failTimer.stop();
        const req = backend._pending;
        if (!req) return;
        if (req.ws.key !== backend._runningKey) {      // stale result for an earlier workspace
            if (!tree.running) backend._start();
            return;
        }
        backend._pending = null;
        req.done(backend._windowsIn(text, req.ws));
    }

    // Walk the i3 tree to the workspace node and collect its leaf windows.
    function _windowsIn(text, ws) {
        let root = null;
        try { root = JSON.parse(text); } catch (e) { return []; }
        const wsNode = backend._findWorkspace(root, ws);
        if (!wsNode) return [];
        const entries = [];
        backend._collect(wsNode, entries);
        return entries;
    }

    function _findWorkspace(node, ws) {
        if (!node) return null;
        if (node.type === "workspace" && (node.name === ws.name || (ws.number >= 0 && node.num === ws.number))) return node;
        for (const list of [node.nodes, node.floating_nodes])
            for (const child of (list || [])) {
                const hit = backend._findWorkspace(child, ws);
                if (hit) return hit;
            }
        return null;
    }

    function _collect(node, entries) {
        for (const list of [node.nodes, node.floating_nodes])
            for (const child of (list || [])) {
                const appId = child.app_id || child.window_properties?.class || "";
                const isLeaf = !(child.nodes && child.nodes.length) && !(child.floating_nodes && child.floating_nodes.length);
                if (isLeaf && appId) entries.push({ appId: appId, title: child.name || "" });
                else backend._collect(child, entries);
            }
    }
}
