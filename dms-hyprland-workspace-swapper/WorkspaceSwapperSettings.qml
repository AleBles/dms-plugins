import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "workspaceSwapper"

    StyledText {
        text: I18n.trFor("workspaceSwapper", "Hyprland Workspace Swapper")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        text: I18n.trFor("workspaceSwapper", "Gives the current workspace a different number. Free numbers are taken straight away; a number that is in use swaps the two workspaces. The popup opens with: dms ipc call workspace-swapper toggle")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    StringSetting {
        settingKey: "keybind"
        label: I18n.trFor("workspaceSwapper", "Key combo")
        description: I18n.trFor("workspaceSwapper", "Hyprland key names joined with +, for example SUPER + CTRL + SHIFT + I (CTRL + SHIFT + I opens developer tools in browsers). The plugin registers the bind itself while it is enabled and puts it back after every Hyprland config reload; nothing is written to your config files. Leave empty if you bind the command in your own Hyprland config, and do not do both: one press would then open and close the popup.")
        defaultValue: ""
        placeholder: "SUPER + CTRL + SHIFT + I"
    }
}
