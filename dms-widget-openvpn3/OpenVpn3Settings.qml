import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "openvpn3"

    StyledText {
        text: I18n.trFor("openvpn3", "OpenVPN 3")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        text: I18n.trFor("openvpn3", "Shows the openvpn3-linux session status in the bar. Click the pill for the profile list (connect, disconnect, import), right-click to toggle the connection. Web-based logins open in your browser.")
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

    ToggleSetting {
        settingKey: "showName"
        label: I18n.trFor("openvpn3", "Show profile name")
        description: I18n.trFor("openvpn3", "Show the name of the connected profile next to the icon (horizontal bars only)")
        defaultValue: true
    }

    SliderSetting {
        settingKey: "nameMaxWidth"
        label: I18n.trFor("openvpn3", "Name width")
        description: I18n.trFor("openvpn3", "Longer profile names are cut with an ellipsis so the pill does not crowd the bar")
        defaultValue: 120
        minimum: 40
        maximum: 300
        unit: "px"
    }

    SliderSetting {
        settingKey: "pollSeconds"
        label: I18n.trFor("openvpn3", "Status refresh")
        description: I18n.trFor("openvpn3", "How often the session status is read from openvpn3 while idle or connected. Connecting sessions and the open popout refresh every second")
        defaultValue: 5
        minimum: 1
        maximum: 30
        unit: "s"
    }

    ToggleSetting {
        settingKey: "autoOpenAuthUrl"
        label: I18n.trFor("openvpn3", "Open login page as fallback")
        description: I18n.trFor("openvpn3", "openvpn3 opens the web login page itself. When it reports that it could not, open the URL it prints (xdg-open). The popout always offers the page under Open login page")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "persistentImport"
        label: I18n.trFor("openvpn3", "Persistent import")
        description: I18n.trFor("openvpn3", "Keep imported profiles across reboots (openvpn3 config-import --persistent)")
        defaultValue: true
    }

    StringSetting {
        settingKey: "defaultProfile"
        label: I18n.trFor("openvpn3", "Default profile")
        description: I18n.trFor("openvpn3", "Profile connected by right-click and by \"dms ipc call openvpn3 toggle\". Leave empty to use the most recently used profile")
        placeholder: I18n.trFor("openvpn3", "most recently used")
    }
}
