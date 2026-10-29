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
        description: "Your Steam Web API key, from steamcommunity.com/dev/apikey"
        placeholder: "Steam API key"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "steamid"
        label: "Steam ID"
        description: "Your Steam ID64 (the 17-digit number), from steamid.io"
        placeholder: "7656119..."
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "showFriendsOnlineText"
        label: "Show \"Friends Online\" text"
        description: "When enabled, the bar shows \"X Friends Online\". When disabled, it just shows the count."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "hideWhenEmpty"
        label: "Hide when no friends are online"
        description: "Hides the bar widget while nobody is online. It still shows if the plugin isn't set up or a fetch fails."
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "notifyOnline"
        label: "Notify when a friend comes online"
        description: "Sends a desktop notification when a friend signs in to Steam"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "notifyGame"
        label: "Notify when a friend starts a game"
        description: "Sends a desktop notification when a friend starts playing something"
        defaultValue: false
    }

    SelectionSetting {
        settingKey: "refreshMinutes"
        label: "Refresh interval"
        description: "How often to check which friends are online"
        options: [
            {label: "1 minute", value: "1"},
            {label: "2 minutes", value: "2"},
            {label: "5 minutes", value: "5"},
            {label: "10 minutes", value: "10"},
            {label: "15 minutes", value: "15"}
        ]
        defaultValue: "5"
    }
}
