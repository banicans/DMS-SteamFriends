import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets



PluginSettings {
    id: root
    pluginId: "steamfriends"

    StyledText {
        width: parent.width
        text: "Steam Friends Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "apikey"
        label: "API Key"
        description: "API_KEY goes here"
        placeholder: "Enter text"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "steamid"
        label: "Steam ID"
        description: "STEAM_ID goes here"
        placeholder: "Enter text"
        defaultValue: ""
    }
}
