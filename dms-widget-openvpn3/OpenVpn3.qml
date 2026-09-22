// OpenVPN 3 — DMS bar widget.
// Shows the state of the openvpn3-linux client in the bar and drives it through the `openvpn3` CLI.
// The popout lists the imported profiles with an on/off toggle and a delete button per profile,
// imports .ovpn files and shows the session status. Status comes from polling `openvpn3 sessions-list`;
// while a session is connecting, waiting for a login, or the popout is open, the poll runs every second.
//
// Web authentication: `openvpn3 session-start` opens the login page in the browser itself and returns;
// the widget only opens the URL when the CLI reports it could not (optional). While the login is pending
// the popout keeps an "Open login page" row (URL from `openvpn3 session-auth`).
// Profiles that ask for a username/password on the terminal are not supported here: start those with
// `openvpn3 session-start -c <profile>` in a terminal and the widget picks the session up.
//
// Right-click on the pill toggles the connection: disconnect the active session, else connect the
// default profile (setting) or the most recently used one.
//
//   dms ipc call openvpn3 status                # "connected azerion", "disconnected", "auth ...", ...
//   dms ipc call openvpn3 toggle                # disconnect, or connect the default profile
//   dms ipc call openvpn3 connect "<profile>"   # profile = configuration name from `openvpn3 configs-list`
//   dms ipc call openvpn3 disconnect
//   dms ipc call openvpn3 refresh
//   dms ipc call openvpn3 popout                # open/close the popout (bind it to a key)
//   dms ipc call openvpn3 importFile ""         # open the file browser; pass a .ovpn path to import it directly
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modals.Common
import qs.Modals.FileBrowser
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "openvpn3"

    // ---- settings (see OpenVpn3Settings.qml) --------------------------------------------
    property bool showName: pluginData.showName ?? true
    property int nameMaxWidth: pluginData.nameMaxWidth ?? 120
    property int pollSeconds: pluginData.pollSeconds ?? 5
    property bool autoOpenAuthUrl: pluginData.autoOpenAuthUrl ?? true
    property bool persistentImport: pluginData.persistentImport ?? true
    property string defaultProfile: pluginData.defaultProfile || ""

    // ---- state ---------------------------------------------------------------------------
    property bool available: true       // `openvpn3` found on PATH
    property var configs: []            // [{ path, name, lastUsed, usedCount }], most recently used first
    property var sessions: []           // [{ path, configName, sessionName, connectedTo, device, statusMajor, statusMinor }]
    property string busyConfig: ""      // profile with a session-start or disconnect in flight
    property string authUrl: ""
    property string openedAuthUrl: ""
    property string lastError: ""
    property var popoutRef: null
    readonly property bool popoutOpen: popoutRef?.shouldBeVisible ?? false

    readonly property var activeSession: sessions.length > 0 ? sessions[0] : null
    readonly property string activeName: activeSession ? activeSession.configName : ""
    // missing | disconnected | connecting | auth | connected | paused | disconnecting | error
    readonly property string state: {
        if (!root.available) return "missing";
        if (!root.activeSession) return "disconnected";
        return root.classify(root.activeSession.statusMinor);
    }
    readonly property bool transitional: root.state === "connecting" || root.state === "auth" || root.state === "disconnecting" || root.busyConfig !== ""

    function tr(term) { return I18n.trFor("openvpn3", term); }

    // Status minor strings printed by `openvpn3 sessions-list` (StatusMinor enum of openvpn3-linux).
    function classify(minor) {
        const m = (minor || "").toLowerCase();
        if (m === "client connected") return "connected";
        if (m.includes("failed") || m.includes("error") || m.includes("process exited") || m.includes("process stopped") || m.includes("process killed") || m === "client disconnected") return "error";
        if (m.includes("authentication") || m.includes("requires user input")) return "auth";
        if (m.includes("paused") || m.includes("pausing")) return "paused";
        if (m.includes("disconnecting")) return "disconnecting";
        return "connecting";    // initialized, connecting, reconnect, resuming, new session created
    }

    readonly property string stateText: {
        switch (root.state) {
        case "missing": return root.tr("openvpn3 is not installed");
        case "connected": return root.tr("Connected to %1").arg(root.activeName);
        case "connecting": return root.tr("Connecting to %1…").arg(root.activeName);
        case "auth": return root.tr("Waiting for web login");
        case "paused": return root.tr("Paused");
        case "disconnecting": return root.tr("Disconnecting…");
        case "error": return root.tr("Connection failed");
        default: return root.busyConfig !== "" ? root.tr("Connecting to %1…").arg(root.busyConfig) : root.tr("Disconnected");
        }
    }
    readonly property string stateDetail: {
        const s = root.activeSession;
        if (!s) return "";
        const parts = [];
        if (s.connectedTo) parts.push(s.connectedTo);
        if (s.device) parts.push(s.device);
        if (root.state === "error" && s.statusMinor) parts.push(s.statusMinor);
        return parts.join(" · ");
    }
    readonly property color stateColor: root.state === "connected" ? Theme.primary : (root.state === "auth" || root.state === "paused") ? Theme.warning : root.state === "error" ? Theme.error : Theme.surfaceText

    // ---- commands -----------------------------------------------------------------------
    // Proc.runCommand only hands back stdout, so stderr is merged in to get openvpn3's "** ERROR **" lines.
    function run(id, args, cb, timeoutMs) {
        Proc.runCommand("openvpn3." + id, ["sh", "-c", 'exec "$@" 2>&1', "sh"].concat(args), cb, 0, timeoutMs ?? 10000, root);
    }
    function fail(text) {
        root.lastError = (text || "").split("\n").map(l => l.replace(/^.*\*\* ERROR \*\*\s*/, "").trim()).filter(l => l !== "").join(" ");
    }

    function checkAvailable(then) {
        run("which", ["sh", "-c", "command -v openvpn3"], (out, code) => {
            root.available = code === 0;
            if (then) then(root.available);
        }, 5000);
    }

    function refreshSessions() {
        if (!root.available) return;
        run("sessions", ["openvpn3", "sessions-list"], (out, code) => {
            if (code !== 0) { root.sessions = []; return; }
            root.sessions = root.parseSessions(out);
            // A session may refer to a profile the list does not know yet (imported elsewhere).
            if (root.activeSession && root.activeName && !root.configs.some(c => c.name === root.activeName)) root.refreshConfigs();
            if ((root.state === "auth" || root.state === "connecting") && root.authUrl === "") root.fetchAuthUrl();
            if (root.state !== "auth" && root.state !== "connecting") root.authUrl = "";
        });
    }

    function refreshConfigs() {
        if (!root.available) return;
        run("configs", ["openvpn3", "configs-list", "--json"], (out, code) => {
            if (code !== 0) return;
            root.configs = root.parseConfigs(out);
        });
    }

    function refreshAll() {
        root.checkAvailable(ok => {
            if (!ok) { root.sessions = []; root.configs = []; return; }
            root.refreshConfigs();
            root.refreshSessions();
        });
    }

    // `openvpn3 session-auth` lists pending authentications with an "Auth URL:" line. The CLI has already
    // opened that page itself, so this only feeds the "Open login page" row.
    function fetchAuthUrl() {
        run("auth", ["openvpn3", "session-auth"], (out, code) => {
            const m = out.match(/Auth URL:\s*(\S+)/);
            if (m) root.setAuthUrl(m[1], false);
        });
    }
    function setAuthUrl(url, openIt) {
        root.authUrl = url;
        if (openIt && root.autoOpenAuthUrl && url !== root.openedAuthUrl) root.openAuthUrl();
    }
    function openAuthUrl() {
        if (root.authUrl === "") return;
        root.openedAuthUrl = root.authUrl;
        Quickshell.execDetached(["xdg-open", root.authUrl]);
    }

    // Records are separated by dashed rules; "Created … PID: …" and "Owner … Device: …" share a line.
    function parseSessions(text) {
        const list = [];
        for (const block of (text || "").split(/^-{5,}\s*$/m)) {
            const s = { path: "", configName: "", sessionName: "", connectedTo: "", device: "", statusMajor: "", statusMinor: "" };
            for (const line of block.split("\n")) {
                for (const part of line.split(/\s{2,}(?=(?:PID|Device):)/)) {
                    const m = part.match(/^\s*([A-Za-z][A-Za-z ]*?):\s*(.*?)\s*$/);
                    if (!m) continue;
                    const val = m[2].startsWith("(") ? "" : m[2];
                    switch (m[1].trim()) {
                    case "Path": s.path = val; break;
                    case "Config name": s.configName = val.replace(/\s*\((Config not available|Current name:.*)\)\s*$/, ""); break;
                    case "Session name": s.sessionName = val; break;
                    case "Connected to": s.connectedTo = val; break;
                    case "Device": s.device = val; break;
                    case "Status": {
                        const i = val.indexOf(",");
                        s.statusMajor = i < 0 ? val : val.slice(0, i).trim();
                        s.statusMinor = i < 0 ? "" : val.slice(i + 1).trim();
                        break;
                    }
                    }
                }
            }
            if (s.path !== "") list.push(s);
        }
        return list;
    }

    // `configs-list --json`: object keyed by configuration path; never used profiles fall back to the import time.
    function parseConfigs(text) {
        let data = {};
        try { data = JSON.parse(text || "{}"); } catch (e) { return []; }
        const entries = Array.isArray(data) ? data.map(c => [c.path || "", c]) : Object.keys(data).map(p => [p, data[p]]);
        const list = entries.map(([path, c]) => ({
            path: path,
            name: (c && c.name) || path.split("/").pop(),
            lastUsed: Number((c && (c.lastused_tstamp ?? c.imported_tstamp)) || 0),
            usedCount: Number((c && c.use_count) || 0)
        })).filter(c => c.path !== "");
        list.sort((a, b) => (b.lastUsed - a.lastUsed) || a.name.localeCompare(b.name));
        return list;
    }

    function sessionFor(name) { return root.sessions.find(s => s.configName === name) || null; }
    function pickDefault() {
        if (root.defaultProfile !== "") return root.defaultProfile;
        return root.configs.length > 0 ? root.configs[0].name : "";
    }

    function startSession(name) {
        if (!name || !root.available || root.busyConfig !== "" || startProc.running) return false;
        root.lastError = "";
        root.authUrl = "";
        root.openedAuthUrl = "";
        root.busyConfig = name;
        startProc.profile = name;
        startProc.running = true;
        return true;
    }

    function stopSession(then) {
        const s = root.activeSession;
        if (!s) return false;
        root.lastError = "";
        root.busyConfig = s.configName || "-";
        run("disconnect", ["openvpn3", "session-manage", "--path", s.path, "--disconnect"], (out, code) => {
            root.busyConfig = "";
            root.authUrl = "";
            if (code !== 0) root.fail(out);
            if (startProc.running) startProc.running = false;
            root.refreshSessions();
            if (code === 0 && then) then();
        }, 30000);
        return true;
    }

    function toggle() {
        if (root.activeSession) return root.stopSession();
        return root.startSession(root.pickDefault());
    }

    // Row click: disconnect the active profile, connect an idle one, or switch when another one is up.
    function profileClicked(cfg) {
        if (root.busyConfig !== "") return;
        if (root.sessionFor(cfg.name)) { root.stopSession(); return; }
        if (root.activeSession) { root.stopSession(() => root.startSession(cfg.name)); return; }
        root.startSession(cfg.name);
    }

    // Delete asks for confirmation; an active profile has to be disconnected first.
    function confirmRemove(cfg) {
        if (root.sessionFor(cfg.name)) { root.fail(root.tr("Disconnect %1 before deleting it").arg(cfg.name)); return; }
        confirmLoader.active = true;
        confirmLoader.item.showWithOptions({
            title: root.tr("Delete profile"),
            message: root.tr("Delete \"%1\" from openvpn3? You can import the .ovpn file again later.").arg(cfg.name),
            confirmText: root.tr("Delete"),
            confirmColor: Theme.error,
            onConfirm: () => root.removeProfile(cfg)
        });
    }
    function removeProfile(cfg) {
        root.lastError = "";
        run("remove", ["openvpn3", "config-remove", "--path", cfg.path, "--force"], (out, code) => {
            if (code !== 0) { root.fail(out || root.tr("Could not delete the profile")); return; }
            ToastService.showInfo(root.tr("Profile deleted"), cfg.name);
            root.refreshConfigs();
        }, 30000);
    }

    function importProfile(filePath) {
        const base = filePath.split("/").pop().replace(/\.(ovpn|conf)$/i, "");
        const cmd = ["openvpn3", "config-import", "-c", filePath, "-n", base].concat(root.persistentImport ? ["-p"] : []);
        run("import", cmd, (out, code) => {
            if (code !== 0) {
                ToastService.showError(root.tr("Import failed"), out.trim());
                return;
            }
            ToastService.showInfo(root.tr("Profile imported"), base);
            root.refreshConfigs();
        }, 30000);
    }

    function openImport() {
        importLoader.active = true;
        if (importLoader.item) importLoader.item.open();
    }
    function toggleImport() {
        if (importLoader.item && importLoader.item.shouldBeVisible) importLoader.item.close();
        else root.openImport();
    }

    // `openvpn3 session-start` as a live process: with web authentication it opens the browser itself and
    // returns; the "Open this URL" line only appears when it could not, and is caught here as it is printed.
    Process {
        id: startProc
        property string profile: ""
        property string errText: ""
        property int exitCode: 0
        property bool exited: false
        property bool errDone: false
        command: ["openvpn3", "session-start", "-c", profile]
        running: false
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/Open this URL to complete the connection:\s*(\S+)/);
                if (m) root.setAuthUrl(m[1], true);
                if (line.includes("** ERROR **")) startProc.errText = (startProc.errText + "\n" + line).trim();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") startProc.errText = (startProc.errText + "\n" + text.trim()).trim();
                startProc.errDone = true;
                startProc.finish();
            }
        }
        onStarted: { errText = ""; exited = false; errDone = false; }
        onExited: (code, status) => { exitCode = code; exited = true; finish(); }
        function finish() {
            if (!exited || !errDone) return;
            root.busyConfig = "";
            if (exitCode !== 0) root.fail(errText || root.tr("Could not start the session"));
            root.refreshSessions();
        }
    }

    Timer {
        interval: root.transitional || root.popoutOpen ? 1000 : Math.max(1, root.pollSeconds) * 1000
        repeat: true
        running: root.available
        onTriggered: root.refreshSessions()
    }

    onPopoutOpenChanged: if (popoutOpen) root.refreshAll()
    Component.onCompleted: root.refreshAll()

    LazyLoader {
        id: confirmLoader
        active: false
        ConfirmModal {}
    }

    LazyLoader {
        id: importLoader
        active: false
        FileBrowserModal {
            browserTitle: root.tr("Import OpenVPN profile")
            browserIcon: "vpn_key"
            browserType: "vpn"
            fileExtensions: ["*.ovpn", "*.conf"]
            onFileSelected: path => root.importProfile(path.replace("file://", ""))
        }
    }

    // ---- pill ---------------------------------------------------------------------------
    readonly property string pillIcon: {
        switch (root.state) {
        case "connected": return "vpn_lock";
        case "auth": return "vpn_key_alert";
        case "error": case "disconnected": case "missing": return root.busyConfig !== "" ? "vpn_key" : "vpn_key_off";
        default: return "vpn_key";
        }
    }
    readonly property color pillColor: root.state === "connected" ? Theme.primary : (root.state === "auth" || root.state === "paused") ? Theme.warning : root.state === "error" ? Theme.error : Theme.widgetIconColor

    pillRightClickAction: function () { root.toggle(); }

    component PillIcon: DankIcon {
        id: pillIconItem
        name: root.pillIcon
        color: root.pillColor
        opacity: root.state === "missing" ? 0.5 : 1
        SequentialAnimation {
            running: root.transitional
            loops: Animation.Infinite
            onStopped: pillIconItem.opacity = root.state === "missing" ? 0.5 : 1
            NumberAnimation { target: pillIconItem; property: "opacity"; to: 0.3; duration: 600 }
            NumberAnimation { target: pillIconItem; property: "opacity"; to: 1.0; duration: 600 }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            PillIcon { size: root.iconSize; anchors.verticalCenter: parent.verticalCenter }
            StyledText {
                visible: root.showName && root.state === "connected" && root.activeName !== ""
                width: Math.min(implicitWidth, Math.max(40, root.nameMaxWidth))
                elide: Text.ElideRight
                text: root.activeName
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        PillIcon { size: root.iconSize; anchors.horizontalCenter: parent.horizontalCenter }
    }

    // ---- popout -------------------------------------------------------------------------
    // A 32 px row: icon + label, optional trailing icon or spinner, highlighted when active.
    component MenuRow: StyledRect {
        id: row
        property string icon: ""
        property string label: ""
        property color tint: Theme.surfaceText
        property bool dimmed: false
        property bool active: false
        property bool busy: false
        property string trailingIcon: ""
        property bool showToggle: false
        property bool toggleChecked: false
        property bool showDelete: false
        signal clicked
        signal deleteClicked
        width: parent.width
        height: 32
        radius: Theme.cornerRadius
        color: active ? (rowMouse.containsMouse ? Theme.primaryPressed : Theme.primaryHoverLight) : (rowMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent")
        border.width: active ? 1 : 0
        border.color: Theme.primary
        opacity: dimmed ? 0.4 : 1
        Row {
            anchors.left: parent.left
            anchors.right: trailingSlot.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS
            DankIcon { anchors.verticalCenter: parent.verticalCenter; name: row.icon; size: 16; color: row.tint }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 16 - Theme.spacingS
                text: row.label
                font.pixelSize: Theme.fontSizeSmall
                color: row.tint
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: row.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: if (!row.dimmed) row.clicked()
        }
        Row {
            id: trailingSlot
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            // Delete: muted until hovered, red on hover. Sits on top of the row's MouseArea.
            Item {
                visible: row.showDelete
                width: 26
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                DankIcon {
                    anchors.centerIn: parent
                    name: "delete"
                    size: 16
                    color: deleteMouse.containsMouse ? Theme.error : Theme.surfaceVariantText
                }
                MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.deleteClicked()
                }
            }
            Item {
                width: row.showToggle ? 38 : (16 + Theme.spacingS)
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                DankSpinner { visible: row.busy && !row.showToggle; anchors.centerIn: parent; size: 14; strokeWidth: 2; color: Theme.primary }
                DankIcon { visible: !row.busy && !row.showToggle && row.trailingIcon !== ""; anchors.centerIn: parent; name: row.trailingIcon; size: 16; color: row.tint }
                DankToggle {
                    visible: row.showToggle
                    anchors.centerIn: parent
                    scale: 0.65
                    checked: row.toggleChecked
                    toggling: row.busy
                    enabled: !row.dimmed
                    onToggled: checked => row.clicked()
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn
            headerText: root.tr("OpenVPN 3")
            onParentPopoutChanged: root.popoutRef = parentPopout

            Column {
                width: parent.width
                spacing: Theme.spacingXS
                bottomPadding: Theme.spacingXS

                Column {
                    width: parent.width
                    leftPadding: Theme.spacingS
                    rightPadding: Theme.spacingS
                    bottomPadding: Theme.spacingXS
                    spacing: 2
                    StyledText {
                        width: parent.width - Theme.spacingS * 2
                        text: root.stateText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: root.stateColor
                        elide: Text.ElideRight
                    }
                    StyledText {
                        visible: text !== ""
                        width: parent.width - Theme.spacingS * 2
                        text: root.stateDetail
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }
                    StyledText {
                        visible: root.lastError !== ""
                        width: parent.width - Theme.spacingS * 2
                        text: root.lastError
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error
                        wrapMode: Text.WordWrap
                    }
                }

                MenuRow {
                    visible: root.authUrl !== ""
                    icon: "open_in_browser"; label: root.tr("Open login page")
                    tint: Theme.primary
                    onClicked: root.openAuthUrl()
                }

                StyledText {
                    visible: root.configs.length === 0
                    width: parent.width - Theme.spacingS * 2
                    leftPadding: Theme.spacingS
                    text: root.available ? root.tr("No profiles imported yet") : root.tr("Install the openvpn3 client and refresh")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: root.configs
                    delegate: MenuRow {
                        required property var modelData
                        readonly property var session: root.sessionFor(modelData.name)
                        readonly property string rowState: session ? root.classify(session.statusMinor) : ""
                        icon: session ? (rowState === "connected" ? "vpn_lock" : rowState === "error" ? "vpn_key_off" : "vpn_key") : "vpn_key"
                        label: modelData.name
                        active: session !== null
                        tint: rowState === "error" ? Theme.error : Theme.surfaceText
                        busy: root.busyConfig === modelData.name || (session !== null && rowState !== "connected" && rowState !== "error" && rowState !== "paused")
                        showToggle: true
                        toggleChecked: session !== null && rowState !== "error"
                        showDelete: session === null
                        dimmed: root.busyConfig !== "" && root.busyConfig !== modelData.name
                        onClicked: root.profileClicked(modelData)
                        onDeleteClicked: root.confirmRemove(modelData)
                    }
                }

                StyledRect {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                MenuRow {
                    icon: "folder_open"; label: root.tr("Import profile…")
                    dimmed: !root.available
                    onClicked: { popoutColumn.closePopout(); root.openImport(); }
                }
                MenuRow {
                    icon: "refresh"; label: root.tr("Refresh")
                    onClicked: root.refreshAll()
                }
            }
        }
    }

    popoutWidth: 300

    // ---- IPC ----------------------------------------------------------------------------
    IpcHandler {
        target: "openvpn3"
        function status(): string { return root.state + (root.activeName !== "" ? " " + root.activeName : ""); }
        function connect(profile: string): string {
            const name = profile || root.pickDefault();
            if (name === "") return "no profile";
            return root.startSession(name) ? "OK" : "busy";
        }
        function disconnect(): string { return root.stopSession() ? "OK" : "no session"; }
        function toggle(): string { return root.toggle() ? "OK" : "nothing to do"; }
        function refresh(): string { root.refreshAll(); return "OK"; }
        function popout(): string { root.triggerPopout(); return "OK"; }
        // importFile "": open/close the file browser; importFile "/path/file.ovpn": import that file directly.
        function importFile(path: string): string {
            if (path === "") { root.toggleImport(); return "OK"; }
            root.importProfile(path);
            return "OK";
        }
    }
}
