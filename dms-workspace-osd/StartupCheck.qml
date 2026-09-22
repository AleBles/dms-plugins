// Startup gate: refuse to enable on a compositor no backend can serve (DMS shows the error as a toast).
// Compositor detection is asynchronous; when it has not finished yet we allow, like DMS itself does.
import QtQuick
import Quickshell.WindowManager
import qs.Common
import qs.Services

QtObject {
    readonly property var supported: ["hyprland", "niri", "mango", "sway", "scroll", "miracle"]

    function check() {
        if (!CompositorService.compositorDetected) return null;
        if (supported.indexOf(CompositorService.compositor) >= 0) return null;
        if ((WindowManager.windowsets?.length ?? 0) > 0) return null;      // ext-workspace-v1 (labwc, ...)
        return {
            title: I18n.trFor("workspaceOsdFlash", "Unsupported compositor"),
            details: I18n.trFor("workspaceOsdFlash", "Workspace OSD Flash needs Hyprland, niri, Mango, sway, Miracle WM, labwc or any compositor with ext-workspace-v1.")
        };
    }
}
