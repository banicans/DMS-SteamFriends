import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginSettings {
    id: root
    pluginId: "steamfriends"

    Column {
        id: mainSettingsCol
        width: parent.width
        spacing: Theme.spacingL

        function loadValue(key, def) {
            return PluginService.loadPluginData(root.pluginId, key, def);
        }

        function saveValue(key, val) {
            PluginService.savePluginData(root.pluginId, key, val);
            PluginService.setGlobalVar(root.pluginId, key, val);
        }

        function loadValueInternal() {
            apiKeyField.loadValue();
            steamIdField.loadValue();
            showFriendsToggle.loadValue();
            onlyShowOnlineToggle.loadValue();
            groupOnlineOfflineToggle.loadValue();
            timeFormatSelector.loadValue();
            showLastOnlineToggle.loadValue();
        }

        Component.onCompleted: loadValueInternal()

        // --- Credentials Group ---
        StyledRect {
            id: credentialsRect
            width: parent.width
            height: Math.max(0, credentialsGroup.implicitHeight + Theme.spacingM * 2)
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
            radius: Theme.cornerRadius
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
            border.width: 1

            Column {
                id: credentialsGroup
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingL

                // API Key Block
                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "vpn_key"
                            size: 22
                            color: Theme.primary
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "Steam Web API Key"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: "Required to fetch friends list and status from Steam API."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    DankTextField {
                        id: apiKeyField
                        width: parent.width
                        placeholderText: "Enter 32-character Steam Web API Key"

                        function loadValue() {
                            text = mainSettingsCol.loadValue("apikey", "");
                        }
                        Component.onCompleted: loadValue()
                        onEditingFinished: {
                            mainSettingsCol.saveValue("apikey", text);
                        }
                    }
                }

                // Steam ID Block
                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "account_circle"
                            size: 22
                            color: Theme.primary
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "Steam 64-bit ID"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: "Your unique 64-bit Steam ID (e.g. 76561198000000000)."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    DankTextField {
                        id: steamIdField
                        width: parent.width
                        placeholderText: "Enter 64-bit Steam ID"

                        function loadValue() {
                            text = mainSettingsCol.loadValue("steamid", "");
                        }
                        Component.onCompleted: loadValue()
                        onEditingFinished: {
                            mainSettingsCol.saveValue("steamid", text);
                        }
                    }
                }
            }
        }

        // --- Display Settings Group ---
        StyledRect {
            id: displayRect
            width: parent.width
            height: Math.max(0, displayGroup.implicitHeight + Theme.spacingM * 2)
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
            radius: Theme.cornerRadius
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
            border.width: 1

            Column {
                id: displayGroup
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingL

                // Show Friends Online Text Toggle
                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "visibility"
                        size: 22
                        color: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Show \"Friends Online\" Text"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: "Display \"X Friends Online\" label instead of only the number."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    DankToggle {
                        id: showFriendsToggle
                        Layout.alignment: Qt.AlignVCenter
                        checked: true

                        function loadValue() {
                            checked = mainSettingsCol.loadValue("showFriendsOnlineText", true);
                        }
                        Component.onCompleted: loadValue()

                        onClicked: {
                            checked = !checked;
                            mainSettingsCol.saveValue("showFriendsOnlineText", checked);
                        }
                    }
                }

                // Only Show Online Friends Toggle
                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "person_search"
                        size: 22
                        color: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Only Show Online Friends"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: "Hide offline friends from the friends list popout."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    DankToggle {
                        id: onlyShowOnlineToggle
                        Layout.alignment: Qt.AlignVCenter
                        checked: false

                        function loadValue() {
                            checked = mainSettingsCol.loadValue("onlyShowOnline", false);
                        }
                        Component.onCompleted: loadValue()

                        onClicked: {
                            checked = !checked;
                            mainSettingsCol.saveValue("onlyShowOnline", checked);
                        }
                    }
                }

                // Group Online & Offline Friends Toggle
                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "table_rows"
                        size: 22
                        color: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Group Online & Offline Friends"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: "Separate online and offline friends into distinct list sections."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    DankToggle {
                        id: groupOnlineOfflineToggle
                        Layout.alignment: Qt.AlignVCenter
                        checked: false

                        function loadValue() {
                            checked = mainSettingsCol.loadValue("groupOnlineOffline", false);
                        }
                        Component.onCompleted: loadValue()

                        onClicked: {
                            checked = !checked;
                            mainSettingsCol.saveValue("groupOnlineOffline", checked);
                        }
                    }
                }

                // Show Last Online Time Toggle
                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "history"
                        size: 22
                        color: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Show Last Online Time"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: "Display relative last online timestamp for offline friends."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    DankToggle {
                        id: showLastOnlineToggle
                        Layout.alignment: Qt.AlignVCenter
                        checked: true

                        function loadValue() {
                            checked = mainSettingsCol.loadValue("showLastOnline", true);
                        }
                        Component.onCompleted: loadValue()

                        onClicked: {
                            checked = !checked;
                            mainSettingsCol.saveValue("showLastOnline", checked);
                        }
                    }
                }

                // Time Format Horizontal Grouped Option Buttons
                Column {
                    id: timeFormatSelector
                    width: parent.width
                    spacing: Theme.spacingS

                    property string currentFormat: "system"

                    function loadValue() {
                        currentFormat = mainSettingsCol.loadValue("timeFormat", "system");
                    }
                    Component.onCompleted: loadValue()

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "schedule"
                            size: 22
                            color: Theme.primary
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "Time Format"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: "Choose time format for timestamps and last online indicators."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: [
                                { title: "System Default", key: "system", icon: "settings_suggest" },
                                { title: "12-Hour", key: "12h", icon: "schedule" },
                                { title: "24-Hour", key: "24h", icon: "alarm" }
                            ]

                            delegate: Item {
                                id: tfItem
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 40

                                property bool isSelected: timeFormatSelector.currentFormat === modelData.key
                                property bool isHovered: tfItemMa.containsMouse

                                Shape {
                                    id: tfItemBg
                                    anchors.fill: parent

                                    property real innerRadius: 4
                                    property real outerRadius: Theme.cornerRadius || 12
                                    property bool isFirst: index === 0
                                    property bool isLast: index === 2

                                    property real tlr: (isSelected || isHovered) ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                    property real blr: (isSelected || isHovered) ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                    property real trr: (isSelected || isHovered) ? (height / 2) : (isLast ? outerRadius : innerRadius)
                                    property real brr: (isSelected || isHovered) ? (height / 2) : (isLast ? outerRadius : innerRadius)

                                    property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                    property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                    property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                    property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }

                                    property color paintColor: isSelected
                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                                            : (isHovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04))

                                    property color paintBorder: isSelected
                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                                            : (isHovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.12))

                                    ShapePath {
                                        fillColor: tfItemBg.paintColor
                                        strokeColor: tfItemBg.paintBorder
                                        strokeWidth: 1

                                        startX: tfItemBg.tlrAnim; startY: 0
                                        PathLine { x: tfItemBg.width - tfItemBg.trrAnim; y: 0 }
                                        PathArc { x: tfItemBg.width; y: tfItemBg.trrAnim; radiusX: tfItemBg.trrAnim; radiusY: tfItemBg.trrAnim; direction: PathArc.Clockwise }
                                        PathLine { x: tfItemBg.width; y: tfItemBg.height - tfItemBg.brrAnim }
                                        PathArc { x: tfItemBg.width - tfItemBg.brrAnim; y: tfItemBg.height; radiusX: tfItemBg.brrAnim; radiusY: tfItemBg.brrAnim; direction: PathArc.Clockwise }
                                        PathLine { x: tfItemBg.blrAnim; y: tfItemBg.height }
                                        PathArc { x: 0; y: tfItemBg.height - tfItemBg.blrAnim; radiusX: tfItemBg.blrAnim; radiusY: tfItemBg.blrAnim; direction: PathArc.Clockwise }
                                        PathLine { x: 0; y: tfItemBg.tlrAnim }
                                        PathArc { x: tfItemBg.tlrAnim; y: 0; radiusX: tfItemBg.tlrAnim; radiusY: tfItemBg.tlrAnim; direction: PathArc.Clockwise }
                                    }
                                }

                                scale: tfItemMa.pressed ? 0.98 : (isHovered ? 1.01 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                DankRipple { id: tfRip; anchors.fill: parent; cornerRadius: tfItemBg.tlrAnim; rippleColor: Theme.primary }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    DankIcon {
                                        name: modelData.icon
                                        size: 16
                                        color: tfItem.isSelected ? Theme.primary : Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: modelData.title
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: tfItem.isSelected ? Font.Bold : Font.Normal
                                        color: tfItem.isSelected ? Theme.primary : Theme.surfaceText
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    id: tfItemMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (m) => tfRip.trigger(m.x, m.y)
                                    onClicked: {
                                        timeFormatSelector.currentFormat = modelData.key;
                                        mainSettingsCol.saveValue("timeFormat", modelData.key);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
