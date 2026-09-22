import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "workspaceOsdFlash"

    StyledText {
        text: I18n.trFor("workspaceOsdFlash", "Workspace OSD Flash")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        text: I18n.trFor("workspaceOsdFlash", "Briefly shows the workspace you switched to, centered on that screen. A new switch replaces the previous one immediately.")
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

    SliderSetting {
        settingKey: "holdMs"
        label: I18n.trFor("workspaceOsdFlash", "Hold time")
        description: I18n.trFor("workspaceOsdFlash", "How long the card stays before fading out")
        defaultValue: 700
        minimum: 200
        maximum: 3000
        unit: "ms"
    }

    SliderSetting {
        settingKey: "fadeMs"
        label: I18n.trFor("workspaceOsdFlash", "Fade-out duration")
        description: I18n.trFor("workspaceOsdFlash", "0 follows the DMS animation speed setting")
        defaultValue: 0
        minimum: 0
        maximum: 1000
        unit: "ms"
    }

    ToggleSetting {
        settingKey: "accentBorder"
        label: I18n.trFor("workspaceOsdFlash", "Accent border")
        description: I18n.trFor("workspaceOsdFlash", "Thin primary-coloured ring around the card, on top of the DMS surface styling")
        defaultValue: true
    }

    SliderSetting {
        settingKey: "fontSize"
        label: I18n.trFor("workspaceOsdFlash", "Text size")
        description: I18n.trFor("workspaceOsdFlash", "The card scales with the text")
        defaultValue: 44
        minimum: 20
        maximum: 96
        unit: "px"
    }

    ToggleSetting {
        settingKey: "showName"
        label: I18n.trFor("workspaceOsdFlash", "Show workspace name")
        description: I18n.trFor("workspaceOsdFlash", "Include the workspace name when it has one")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showApps"
        label: I18n.trFor("workspaceOsdFlash", "List open windows")
        description: I18n.trFor("workspaceOsdFlash", "Show the windows open on that workspace, one per line, under the label")
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "appLineStyle"
        label: I18n.trFor("workspaceOsdFlash", "App lines show")
        description: I18n.trFor("workspaceOsdFlash", "One line per window with its title, or app names grouped with a count")
        options: [
            { label: I18n.trFor("workspaceOsdFlash", "Window titles (App · Title)"), value: "title" },
            { label: I18n.trFor("workspaceOsdFlash", "App names only"), value: "name" }
        ]
        defaultValue: "title"
    }

    SelectionSetting {
        settingKey: "appLineAlign"
        label: I18n.trFor("workspaceOsdFlash", "App lines alignment")
        description: I18n.trFor("workspaceOsdFlash", "Alignment of the window list under the label")
        options: [
            { label: I18n.trFor("workspaceOsdFlash", "Left"), value: "left" },
            { label: I18n.trFor("workspaceOsdFlash", "Center"), value: "center" }
        ]
        defaultValue: "left"
    }

    SliderSetting {
        settingKey: "appLineMaxChars"
        label: I18n.trFor("workspaceOsdFlash", "Max characters per line")
        description: I18n.trFor("workspaceOsdFlash", "Longer lines are cut with an ellipsis; 0 disables the limit")
        defaultValue: 100
        minimum: 0
        maximum: 300
    }

    SliderSetting {
        settingKey: "maxApps"
        label: I18n.trFor("workspaceOsdFlash", "Max lines")
        description: I18n.trFor("workspaceOsdFlash", "Further windows are folded into \"+N more\"")
        defaultValue: 6
        minimum: 1
        maximum: 12
    }

    SelectionSetting {
        settingKey: "labelStyle"
        label: I18n.trFor("workspaceOsdFlash", "Label style")
        description: I18n.trFor("workspaceOsdFlash", "How the number and name are combined")
        options: [
            { label: I18n.trFor("workspaceOsdFlash", "Workspace 2: work"), value: "prefixed" },
            { label: I18n.trFor("workspaceOsdFlash", "2 · work"), value: "compact" },
            { label: I18n.trFor("workspaceOsdFlash", "Name only (number if unnamed)"), value: "nameOnly" }
        ]
        defaultValue: "prefixed"
    }

    SelectionSetting {
        settingKey: "position"
        label: I18n.trFor("workspaceOsdFlash", "Position")
        description: I18n.trFor("workspaceOsdFlash", "Where the card appears on the screen")
        options: [
            { label: I18n.trFor("workspaceOsdFlash", "Center"), value: "center" },
            { label: I18n.trFor("workspaceOsdFlash", "Top"), value: "top" },
            { label: I18n.trFor("workspaceOsdFlash", "Bottom"), value: "bottom" }
        ]
        defaultValue: "center"
    }
}
