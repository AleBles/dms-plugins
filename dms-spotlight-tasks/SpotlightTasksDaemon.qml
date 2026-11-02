// Spotlight Tasks — the socket half.
//
// Holds one connection to `dagr serve` (a Unix socket speaking one JSON object
// per line), keeps a cache of the open task list, and performs the commands the
// launcher half asks for.
//
// This is the *daemon* surface on purpose. Launcher surfaces are only created
// the first time someone opens the launcher, so a connection living there would
// miss every change until then and the first search would come up empty. Daemon
// surfaces are instantiated once, at shell start.
//
// The two surfaces are separate objects, so they talk through plugin global
// variables: this one publishes `tasks` / `online`, and watches `cmd` for work.
//
//   dms ipc call tasks add "buy bread"     # add without opening the launcher
//   dms ipc call tasks status              # is the service reachable?
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Common
import qs.Services

Item {
    id: root

    property var pluginService: null
    readonly property string pluginId: "spotlightTasks"

    // Where `dagr serve` listens. Overridable so a development build started
    // with DAGR_SOCKET can be followed instead of the installed one.
    property string socketPath: ""
    property bool confirmToasts: true

    property int _nextId: 0
    // request id -> "snapshot", or the toast to show when the reply arrives
    property var _inflight: ({})
    property int _lastCmdSeq: 0

    function tr(term) {
        return I18n.trFor("spotlightTasks", term);
    }

    // ---- settings -------------------------------------------------------------------------
    function _defaultSocketPath() {
        const run = Quickshell.env("XDG_RUNTIME_DIR");
        return (run && run.length > 0 ? run : "/tmp") + "/dagr/dagr.sock";
    }

    function _loadSettings() {
        if (!pluginService)
            return;
        const get = (key, def) => pluginService.loadPluginData(pluginId, key, def);
        const configured = (get("socketPath", "") || "").trim();
        socketPath = configured.length > 0 ? configured : _defaultSocketPath();
        confirmToasts = get("confirmToasts", true) === true;
    }

    Component.onCompleted: {
        socketPath = _defaultSocketPath();
        _publish("online", false);
        _loadSettings();
    }
    onPluginServiceChanged: _loadSettings()

    property Connections _settingsConn: Connections {
        target: root.pluginService
        enabled: root.pluginService !== null

        function onPluginDataChanged(id) {
            if (id === root.pluginId)
                root._loadSettings();
        }

        // How the launcher half asks for something to be done: it cannot reach
        // this socket directly. `seq` makes two identical commands in a row
        // still register as a change.
        function onGlobalVarChanged(id, name) {
            if (id !== root.pluginId || name !== "cmd")
                return;
            const cmd = root.pluginService.getGlobalVar(root.pluginId, "cmd", null);
            if (!cmd || !cmd.method || cmd.seq === root._lastCmdSeq)
                return;
            root._lastCmdSeq = cmd.seq;
            root.request(cmd.method, cmd.params, cmd.toast || "");
        }
    }

    // ---- the socket -----------------------------------------------------------------------
    function _publish(name, value) {
        if (pluginService)
            pluginService.setGlobalVar(pluginId, name, value);
    }

    // Returns the request id, or -1 when the service is not reachable.
    function request(method, params, toast) {
        if (!socket.linkUp) {
            if (toast)
                ToastService.showError(tr("Dagr is not running"));
            return -1;
        }
        _nextId += 1;
        _inflight[_nextId] = toast === undefined ? "" : toast;
        socket.send({
            id: _nextId,
            method: method,
            params: params || ({})
        });
        return _nextId;
    }

    function refresh() {
        _nextId += 1;
        _inflight[_nextId] = "snapshot";
        socket.send({
            id: _nextId,
            method: "list_tasks",
            params: {
                include_done: false
            }
        });
    }

    function _handle(text) {
        if (!text || text.length === 0)
            return;
        let message;
        try {
            message = JSON.parse(text);
        } catch (e) {
            console.warn("spotlightTasks: could not parse", text);
            return;
        }

        if (message.event !== undefined) {
            if (message.event === "hello") {
                if (message.protocol !== 1)
                    console.warn("spotlightTasks: unknown protocol", message.protocol, "- update the plugin");
                // Which database is being served: worth surfacing, because a
                // development build and a Flatpak build have different ones.
                _publish("db", message.db || "");
            } else if (message.event === "changed" || message.event === "resync") {
                // Coalesce bursts: one edit can produce several events.
                refreshDebounce.restart();
            }
            return;
        }

        const toast = _inflight[message.id];
        delete _inflight[message.id];

        if (message.ok === false) {
            const reason = message.error && message.error.message ? message.error.message : tr("unknown error");
            if (toast !== undefined && toast !== "snapshot")
                ToastService.showError("Dagr: " + reason);
            else
                console.warn("spotlightTasks:", reason);
            return;
        }

        if (toast === "snapshot" && message.result) {
            _publish("tasks", message.result.tasks || []);
            _publish("priorities", message.result.priorities || []);
            _publish("settings", message.result.settings || ({}));
            _publish("online", true);
        } else if (toast && confirmToasts) {
            ToastService.showInfo(toast);
        }
    }

    property Timer _refreshDebounce: Timer {
        id: refreshDebounce
        interval: 100
        repeat: false
        onTriggered: root.refresh()
    }

    // DSocket rather than a bare Quickshell Socket: it reconnects with
    // backoff, and works around a Socket that cannot redial after a failed
    // attempt. That matters here because the service may well start after the
    // shell does.
    property DSocket _socket: DSocket {
        id: socket

        path: root.socketPath
        connected: root.socketPath.length > 0

        onConnectionStateChanged: {
            if (linkUp) {
                root._inflight = ({});
                // Subscribe before listing, so nothing that happens during the
                // first listing is missed.
                socket.send({
                    id: 0,
                    method: "subscribe",
                    params: {}
                });
                root.refresh();
            } else {
                root._publish("online", false);
            }
        }

        parser: SplitParser {
            onRead: line => root._handle(line)
        }
    }

    // ---- ipc ------------------------------------------------------------------------------
    property IpcHandler _ipc: IpcHandler {
        target: "tasks"

        // Add without opening the launcher. Leading `!` marks still apply, so
        // `dms ipc call tasks add "!! pay rent"` raises the priority.
        function add(title: string): string {
            const text = (title || "").trim();
            if (text === "")
                return "usage: dms ipc call tasks add \"<task>\"";
            return root.request("add_task", {
                title: text
            }, root.tr("Added") + " \"" + text + "\"") > 0 ? "OK" : "dagr is not running";
        }

        function status(): string {
            if (!socket.linkUp)
                return "offline (" + root.socketPath + ")";
            const tasks = root.pluginService ? root.pluginService.getGlobalVar(root.pluginId, "tasks", []) : [];
            return "online, " + tasks.length + " open";
        }

        function refresh(): string {
            root.refresh();
            return "OK";
        }
    }
}
