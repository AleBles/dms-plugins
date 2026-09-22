// Workspace OSD Flash — DMS daemon plugin.
// Flashes the id/name of the workspace you just switched to, centered on that screen.
// A new switch replaces the text immediately (no queue); the card fades out after `holdMs`.
//
// Compositors are pluggable: one backend from backends/ is loaded for the detected compositor
// (Hyprland, niri, Mango, sway/scroll/Miracle WM via i3 IPC, and ext-workspace-v1 for labwc and
// anything else). See backends/WorkspaceBackend.qml for the contract and how to add one.
// Below the label it lists the windows open on that workspace, one per line in a small font
// ("App · Window title", or grouped app names), folding the rest into "+N more".
// IPC (all three arguments are required, pass "" to skip one):
//   dms ipc call wsosd flash "<text>" "<monitor-name or empty for all>" "line one | line two"
//   dms ipc call wsosd hide
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "Labels.js" as Labels

PluginComponent {
    id: root
    readonly property var log: Log.scoped("WorkspaceOsdFlash")

    // ---- settings (see WorkspaceOsdSettings.qml) --------------------------------------
    property int holdMs: pluginData.holdMs ?? 700
    // 0 = follow the DMS animation speed setting
    property int fadeSetting: pluginData.fadeMs ?? 0
    readonly property int fadeMs: fadeSetting > 0 ? fadeSetting : Theme.mediumDuration
    property int fontSize: pluginData.fontSize ?? 44
    property bool showName: pluginData.showName ?? true
    property string labelStyle: pluginData.labelStyle || "prefixed"   // prefixed | compact | nameOnly
    property string position: pluginData.position || "center"        // center | top | bottom
    property bool showApps: pluginData.showApps ?? true
    property bool accentBorder: pluginData.accentBorder ?? true
    property int maxApps: pluginData.maxApps ?? 6
    property string appLineStyle: pluginData.appLineStyle || "title"   // title | name
    property string appLineAlign: pluginData.appLineAlign || "left"    // left | center
    property int appLineMaxChars: pluginData.appLineMaxChars ?? 100    // 0 = no limit

    // Translated templates for Labels.js (literal plugin id so the extraction tooling sees them).
    readonly property var labelOpts: ({
        showName: root.showName,
        labelStyle: root.labelStyle,
        prefixed: I18n.trFor("workspaceOsdFlash", "Workspace %1: %2"),
        plain: I18n.trFor("workspaceOsdFlash", "Workspace %1")
    })
    readonly property var lineOpts: ({
        appLineStyle: root.appLineStyle,
        maxApps: root.maxApps,
        appLineMaxChars: root.appLineMaxChars,
        more: I18n.trFor("workspaceOsdFlash", "+%1 more")
    })

    // ---- flash state --------------------------------------------------------------------
    property string text: ""
    property var apps: []
    property string monitor: ""
    property bool shown: false
    property bool fading: false
    property string currentKey: ""       // workspace key of the flash being shown (late window lists check it)

    Timer { id: hideTimer; interval: root.holdMs; onTriggered: root.shown = false }
    Timer { id: unmapTimer; interval: root.fadeMs + 80; onTriggered: root.fading = false }
    onShownChanged: {
        if (shown) { unmapTimer.stop(); fading = false; }
        else { fading = true; unmapTimer.restart(); }
    }

    // Show the card (a new call replaces the current text; nothing is queued).
    function showFlash(text, monitor, apps) {
        if (SessionData.suppressOSD) return;
        root.text = text;
        root.apps = root.showApps ? (apps || []) : [];
        root.monitor = monitor || "";
        root.shown = true;
        hideTimer.restart();
    }

    function appName(appId) {
        if (!appId) return "";
        const modded = Paths.moddedAppId(appId);
        return Paths.getAppName(modded, DesktopEntries.heuristicLookup(modded));
    }

    // ---- compositor backend ----------------------------------------------------------------
    // CompositorService.compositor -> backends/<Name>Backend.qml; anything unknown gets the
    // ext-workspace-v1 backend. Adding a compositor = a new file here plus one entry.
    readonly property var backendFor: ({
        hyprland: "Hyprland",
        niri: "Niri",
        mango: "Mango",
        sway: "Sway",
        scroll: "Sway",
        miracle: "Sway"
    })
    Loader {
        id: backend
        active: CompositorService.compositorDetected
        source: active ? "backends/" + (root.backendFor[CompositorService.compositor] ?? "ExtWorkspace") + "Backend.qml" : ""
        onStatusChanged: {
            if (status === Loader.Error) root.log.warn("backend failed to load:", source);
            else if (status === Loader.Ready) root.log.info("backend", item.name, "for", CompositorService.compositor, item.available ? "" : "(not available on this session)");
        }
    }
    Connections {
        target: backend.item
        function onWorkspaceActivated(ws) { root.onWorkspace(ws); }
    }

    // A backend reported a switch: show the label now, add the window lines when they arrive.
    function onWorkspace(ws) {
        const label = Labels.labelFor(ws.number, ws.name, root.labelOpts);
        const out = ws.output || "";
        root.currentKey = ws.key;
        root.showFlash(label, out, []);
        const finish = all => {
            // DMS's own toplevels (its hidden tray window etc.) are not windows the user cares about.
            const entries = all.filter(e => e.appId !== "com.danklinux.dms" && e.appId !== "org.quickshell");
            const lines = Labels.summarize(entries.map(e => ({ name: root.appName(e.appId), title: e.title })), root.lineOpts);
            if (root.currentKey === ws.key && root.shown) root.apps = root.showApps ? lines : [];
            root.log.info("flash", JSON.stringify(label), "on", out || "all screens", "-", entries.length, "windows");
        };
        if (!root.showApps || !backend.item) { finish([]); return; }
        backend.item.listWindows(ws, finish);
    }

    // ---- IPC ----------------------------------------------------------------------------
    IpcHandler {
        target: "wsosd"
        // apps: list of lines separated by "|" (or newlines); pass "" for none. Quickshell IPC needs all arguments.
        function flash(text: string, monitor: string, apps: string): void {
            const lines = (apps || "").split(/\s*\|\s*|\n/).map(a => a.trim()).filter(a => a !== "");
            root.currentKey = "ipc";
            root.showFlash(text, monitor, Labels.summarize(lines.map(l => ({ name: "", title: l })), root.lineOpts));
        }
        function hide(): void { root.shown = false; }
    }

    // ---- overlay window, one per screen --------------------------------------------------
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool forThisScreen: root.monitor === "" || root.monitor === modelData.name
            readonly property bool active: root.shown && forThisScreen

            // Same layer selection as DMS's own OSDs (DMS_OSD_LAYER env override, overlay default).
            WlrLayershell.layer: LayerShell.fromEnv("DMS_OSD_LAYER", WlrLayer.Overlay, { "allow": ["top", "overlay"], "invalidLayer": WlrLayer.Overlay, "label": "Workspace OSD" })
            WlrLayershell.namespace: "dms:osd"
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}                                   // click-through
            visible: forThisScreen && (root.shown || root.fading)
            anchors.top: root.position === "top"
            anchors.bottom: root.position === "bottom"
            margins.top: root.position === "top" ? 96 : 0
            margins.bottom: root.position === "bottom" ? 96 : 0

            readonly property real dpr: CompositorService.getScreenScale(modelData)
            readonly property real shadowBuffer: 15
            readonly property real cardWidth: Theme.px(content.implicitWidth + Math.round(root.fontSize * 1.6), dpr)
            readonly property real cardHeight: Theme.px(content.implicitHeight + Math.round(root.fontSize * 0.9), dpr)
            implicitWidth: cardWidth + shadowBuffer * 2
            implicitHeight: cardHeight + shadowBuffer * 2

            // Background blur behind the card (only when the user enabled blur in DMS).
            WindowBlur {
                targetWindow: win
                blurX: win.shadowBuffer
                blurY: win.shadowBuffer
                blurWidth: win.active ? win.cardWidth : 0
                blurHeight: win.active ? win.cardHeight : 0
                blurRadius: Theme.cornerRadius
            }

            Item {
                id: card
                x: win.shadowBuffer
                y: win.shadowBuffer
                width: win.cardWidth
                height: win.cardHeight
                opacity: 1
                scale: 1
                // Appear instantly (animations do not run reliably on a window that is being mapped);
                // fade + shrink out explicitly when deactivated, using the DMS easing.
                ParallelAnimation {
                    id: fadeOut
                    NumberAnimation {
                        target: card
                        property: "opacity"
                        to: 0
                        duration: root.fadeMs
                        easing.type: Theme.emphasizedEasing
                    }
                    NumberAnimation {
                        target: card
                        property: "scale"
                        to: 0.9
                        duration: root.fadeMs
                        easing.type: Theme.emphasizedEasing
                    }
                }
                Connections {
                    target: win
                    function onActiveChanged() {
                        if (win.active) { fadeOut.stop(); card.opacity = 1; card.scale = 1; }
                        else if (win.visible) { fadeOut.restart(); }
                    }
                }

                // Surface: theme corner radius, popup transparency, outline, M3 elevation shadow.
                ElevationShadow {
                    anchors.fill: parent
                    level: Theme.elevationLevel3
                    fallbackOffset: 6
                    targetRadius: Theme.cornerRadius
                    targetColor: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
                    borderColor: Theme.outlineMedium
                    borderWidth: 1
                    shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
                }
                // Blur border (follows the DMS "blur border" colour/enabled settings).
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius
                    color: "transparent"
                    border.color: BlurService.borderColor
                    border.width: BlurService.borderWidth
                }
                // Accent: thin primary-coloured ring so the flash reads as a highlight, not a popup.
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius
                    color: "transparent"
                    border.color: Theme.withAlpha(Theme.primary, 0.6)
                    border.width: root.accentBorder ? 1 : 0
                }

                Column {
                    id: content
                    anchors.centerIn: parent
                    spacing: Math.round(root.fontSize * 0.18)
                    Text {
                        id: label
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.text
                        color: Theme.surfaceText
                        font.family: Theme.fontFamily
                        font.pixelSize: root.fontSize
                        font.weight: Font.DemiBold
                    }
                    Column {
                        id: appsList
                        // Block of lines centered under the label; lines are left-aligned inside it (or centered, per setting).
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: contentWidth
                        visible: root.apps.length > 0
                        spacing: Math.round(root.fontSize * 0.08)
                        topPadding: Math.round(root.fontSize * 0.1)
                        readonly property real maxLineWidth: Math.round(win.screen.width * 0.5)
                        property real contentWidth: 0
                        function recompute() {
                            let w = 0;
                            for (let i = 0; i < appsRepeater.count; i++) {
                                const it = appsRepeater.itemAt(i);
                                if (it) w = Math.max(w, Math.min(it.implicitWidth, maxLineWidth));
                            }
                            contentWidth = w;
                        }
                        Repeater {
                            id: appsRepeater
                            model: root.apps
                            onItemAdded: Qt.callLater(appsList.recompute)
                            onItemRemoved: Qt.callLater(appsList.recompute)
                            Text {
                                required property string modelData
                                text: modelData
                                color: Theme.surfaceVariantText
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.max(Theme.fontSizeSmall, Math.round(root.fontSize * 0.38))
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                width: appsList.contentWidth > 0 ? appsList.contentWidth : Math.min(implicitWidth, appsList.maxLineWidth)
                                horizontalAlignment: root.appLineAlign === "center" ? Text.AlignHCenter : Text.AlignLeft
                                onImplicitWidthChanged: Qt.callLater(appsList.recompute)
                            }
                        }
                    }
                }
            }
        }
    }
}
