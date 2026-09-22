import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "spotlightTasks"

    StyledText {
        text: I18n.trFor("spotlightTasks", "Spotlight Tasks")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        text: I18n.trFor("spotlightTasks", "Type the trigger in the launcher to search your open Dagr tasks; whatever you type is also offered as a new task. Enter on a task marks it done. Bind a key to: dms ipc call spotlight toggleQuery \"+ \"")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
    }

    StyledText {
        text: I18n.trFor("spotlightTasks", "Needs Dagr's background service: systemctl --user enable --now dagr")
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
        settingKey: "trigger"
        label: I18n.trFor("spotlightTasks", "Trigger")
        description: I18n.trFor("spotlightTasks", "Typed first in the launcher to show only this plugin. Use a symbol: a letter would hijack every search starting with it. Update your keybind when you change it.")
        defaultValue: "+"
        placeholder: "+"
    }

    ToggleSetting {
        settingKey: "noTrigger"
        label: I18n.trFor("spotlightTasks", "No trigger (always show)")
        description: I18n.trFor("spotlightTasks", "Also list tasks among the normal launcher results")
        defaultValue: false
    }

    SliderSetting {
        settingKey: "maxTasks"
        label: I18n.trFor("spotlightTasks", "Tasks listed")
        description: I18n.trFor("spotlightTasks", "How many matching tasks to show at once")
        defaultValue: 20
        minimum: 5
        maximum: 100
    }

    ToggleSetting {
        settingKey: "confirmToasts"
        label: I18n.trFor("spotlightTasks", "Confirm with a toast")
        description: I18n.trFor("spotlightTasks", "Show a notification after adding, completing or deleting. Errors are always shown.")
        defaultValue: true
    }

    StringSetting {
        settingKey: "socketPath"
        label: I18n.trFor("spotlightTasks", "Socket path")
        description: I18n.trFor("spotlightTasks", "Empty uses the default, $XDG_RUNTIME_DIR/dagr/dagr.sock. Set this to follow a development build started with DAGR_SOCKET.")
        defaultValue: ""
        placeholder: "$XDG_RUNTIME_DIR/dagr/dagr.sock"
    }
}
