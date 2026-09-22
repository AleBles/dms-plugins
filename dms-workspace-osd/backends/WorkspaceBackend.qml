// Contract every compositor backend implements. The daemon loads exactly one backend
// (see `backendFor` in WorkspaceOsd.qml) and only talks to it through this surface.
//
// To add a compositor: create backends/<Name>Backend.qml deriving from this type, emit
// `workspaceActivated` when the active workspace of an output changes, and (optionally)
// implement `listWindows`. Then add the CompositorService name to the map in WorkspaceOsd.qml.
import QtQuick

Item {
    id: backend
    visible: false

    // Short name for log lines.
    property string name: "none"
    // True when this backend can work in the current session.
    property bool available: false

    // ws = { key: string, number: int (-1 when the workspace only has a name), name: string,
    //        output: string (screen name, "" = all screens) } plus backend-private fields.
    signal workspaceActivated(var ws)

    // Windows open on `ws`: done([{ appId, title }]). May call `done` synchronously or later;
    // the default reports none (ext-workspace has no window mapping).
    function listWindows(ws, done) {
        done([]);
    }
}
