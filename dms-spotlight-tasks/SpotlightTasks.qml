// Spotlight Tasks — the launcher half.
//
// Type the trigger (default "+") in the DMS launcher to search your open Dagr
// tasks. Whatever you type is also offered as "Add task", so the plugin is
// useful even when nothing matches. Enter on a task marks it done.
//
// `getItems` is called synchronously on every keystroke, so it does no I/O at
// all: it reads the cache that SpotlightTasksDaemon keeps filled over the
// socket. Adding a socket here instead would look simpler and would be wrong —
// see the note at the top of SpotlightTasksDaemon.qml.
//
// Matching and ranking are done here through `_preScored`, because the
// launcher's scorer uses that value verbatim.
//
//   dms ipc call spotlight toggleQuery "+ "        # open pre-filled with the trigger
//   dms ipc call tasks add "buy bread"             # add without opening anything
pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

QtObject {
    id: root

    // ---- launcher plugin contract ---------------------------------------------------------
    property var pluginService: null
    readonly property string pluginId: "spotlightTasks"
    property string trigger: "+"
    signal itemsChanged

    // ---- settings -------------------------------------------------------------------------
    property int maxTasks: 20

    function tr(term) {
        return I18n.trFor("spotlightTasks", term);
    }

    function _loadSettings() {
        if (!pluginService)
            return;
        const get = (key, def) => pluginService.loadPluginData(pluginId, key, def);
        const noTrigger = get("noTrigger", false) === true;
        trigger = noTrigger ? "" : (get("trigger", "+") || "+");
        maxTasks = get("maxTasks", 20);
    }
    Component.onCompleted: _loadSettings()
    onPluginServiceChanged: _loadSettings()

    property Connections _settingsConn: Connections {
        target: root.pluginService
        enabled: root.pluginService !== null

        function onPluginDataChanged(id) {
            if (id !== root.pluginId)
                return;
            root._loadSettings();
            root.itemsChanged();
        }

        // The daemon half republishes the cache after every change; tell the
        // launcher to ask us again so an open list updates in place.
        function onGlobalVarChanged(id, name) {
            if (id === root.pluginId && (name === "tasks" || name === "online"))
                root.itemsChanged();
        }
    }

    // ---- the cache ------------------------------------------------------------------------
    function _cached(name, fallback) {
        return pluginService ? pluginService.getGlobalVar(pluginId, name, fallback) : fallback;
    }

    // `priority` is absent entirely when the priority feature is switched off
    // in Dagr, so nothing may reach into it blindly.
    function _priorityName(task) {
        return task.priority && task.priority.name ? task.priority.name : "";
    }

    function _comment(task) {
        const priority = _priorityName(task);
        return priority !== "" ? priority + " · " + tr("Enter to complete") : tr("Enter to complete");
    }

    // ---- items ----------------------------------------------------------------------------
    function getItems(query) {
        const text = (query || "").trim();

        if (!_cached("online", false))
            return [
                {
                    name: tr("Dagr is not running"),
                    icon: "material:cloud_off",
                    comment: tr("Start it with: systemctl --user start dagr"),
                    action: "none:",
                    categories: ["Spotlight Tasks"]
                }
            ];

        const items = [];

        // Adding comes first: it is the reason the plugin exists, and the only
        // thing that still works when nothing matches. The text goes through
        // untouched, so `+ !! pay rent` gets its priority from Dagr itself.
        if (text.length > 0)
            items.push({
                name: tr("Add task") + ": " + text,
                icon: "material:add_task",
                comment: tr("Leading ! marks raise the priority"),
                action: "add:" + text,
                categories: ["Spotlight Tasks"],
                _preScored: 1000
            });

        const needle = text.toLowerCase();
        const tasks = _cached("tasks", []);
        let rank = 900;
        for (let i = 0; i < tasks.length && items.length <= maxTasks; i++) {
            const task = tasks[i];
            if (needle.length > 0 && task.title.toLowerCase().indexOf(needle) === -1)
                continue;
            items.push({
                id: String(task.id),
                kind: "task",
                taskId: task.id,
                name: task.title,
                icon: "material:radio_button_unchecked",
                comment: _comment(task),
                action: "done:" + task.id,
                categories: ["Spotlight Tasks"],
                keywords: [_priorityName(task)].filter(k => k !== ""),
                _preScored: rank--
            });
        }

        if (items.length === 0)
            items.push({
                name: tr("No open tasks"),
                icon: "material:check_circle",
                comment: tr("Type to add one"),
                action: "none:",
                categories: ["Spotlight Tasks"]
            });

        return items;
    }

    function executeItem(item) {
        if (!item || !item.action)
            return;
        const separator = item.action.indexOf(":");
        const kind = item.action.slice(0, separator);
        const data = item.action.slice(separator + 1);

        if (kind === "add")
            _post("add_task", {
                title: data
            }, tr("Added") + " \"" + data + "\"");
        else if (kind === "done")
            _post("update_task", {
                id: parseInt(data, 10),
                done: true
            }, tr("Completed") + " \"" + item.name + "\"");
    }

    function getContextMenuActions(item) {
        if (!item || item.kind !== "task")
            return [];
        return [
            {
                icon: "delete",
                text: tr("Delete task"),
                closeLauncher: true,
                action: () => root._post("delete_task", {
                        id: item.taskId
                    }, root.tr("Deleted") + " \"" + item.name + "\"")
            }
        ];
    }

    // The socket lives in the daemon half, so hand it the command through the
    // shared variables. `seq` makes two identical commands in a row still
    // register as a change.
    function _post(method, params, toast) {
        if (!pluginService)
            return;
        const seq = pluginService.getGlobalVar(pluginId, "seq", 0) + 1;
        pluginService.setGlobalVar(pluginId, "seq", seq);
        pluginService.setGlobalVar(pluginId, "cmd", {
            seq: seq,
            method: method,
            params: params,
            toast: toast
        });
    }

    // `dms ipc call plugins toggle spotlightTasks`
    function toggle() {
        PopoutService.toggleDankLauncherV2WithQuery(trigger !== "" ? trigger + " " : "");
    }
}
