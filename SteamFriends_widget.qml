import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 420

    // Count and raw friend list
    property string friendCount: "0"
    property var friendsList: []
    property var sortedFriendsList: []
    property var friendGroups: [] // Grouped lists for separate containers
    property string errorMessage: ""
    property var lastUpdated: null
    property bool isRefreshing: false

    property string scriptPath: Qt.resolvedUrl("steam_friends.sh").toString().replace("file://", "")
    
    // Load settings with fallback
    property string apiKey: PluginService.loadPluginData("steamfriends", "apikey", "")
    property string steamId: PluginService.loadPluginData("steamfriends", "steamid", "")
    property bool showFriendsOnlineText: PluginService.loadPluginData("steamfriends", "showFriendsOnlineText", true)
    property bool onlyShowOnline: PluginService.loadPluginData("steamfriends", "onlyShowOnline", false)
    property bool groupOnlineOffline: PluginService.loadPluginData("steamfriends", "groupOnlineOffline", false)
    property string timeFormat: PluginService.loadPluginData("steamfriends", "timeFormat", "system")
    property bool showLastOnline: PluginService.loadPluginData("steamfriends", "showLastOnline", true)

    // Saved Sort Preferences
    property int sortOrder: PluginService.loadPluginData("steamfriends", "sortOrder", 1)
    property bool alphaSortAscending: PluginService.loadPluginData("steamfriends", "alphaSortAscending", true)
    property bool statusSortAscending: PluginService.loadPluginData("steamfriends", "statusSortAscending", true)
    readonly property bool effectiveSortAscending: root.sortOrder === 0 ? root.alphaSortAscending : root.statusSortAscending

    // Reactivity
    PluginGlobalVar { varName: "apikey"; onValueChanged: { root.apiKey = value; root.refreshFetcher() } }
    PluginGlobalVar { varName: "steamid"; onValueChanged: { root.steamId = value; root.refreshFetcher() } }
    PluginGlobalVar { varName: "showFriendsOnlineText"; onValueChanged: { root.showFriendsOnlineText = value } }
    PluginGlobalVar { varName: "onlyShowOnline"; onValueChanged: { root.onlyShowOnline = value; root.updateSortedList() } }
    PluginGlobalVar { varName: "groupOnlineOffline"; onValueChanged: { root.groupOnlineOffline = value; root.updateSortedList() } }
    PluginGlobalVar { varName: "timeFormat"; onValueChanged: { root.timeFormat = value; root.updateSortedList() } }
    PluginGlobalVar { varName: "showLastOnline"; onValueChanged: { root.showLastOnline = value; root.updateSortedList() } }
    PluginGlobalVar { varName: "sortOrder"; onValueChanged: { root.sortOrder = value; root.updateSortedList() } }
    PluginGlobalVar { varName: "alphaSortAscending"; onValueChanged: { root.alphaSortAscending = value; root.updateSortedList() } }
    PluginGlobalVar { varName: "statusSortAscending"; onValueChanged: { root.statusSortAscending = value; root.updateSortedList() } }

    onPluginDataChanged: {
        if (!pluginData) return;
        root.apiKey = PluginService.loadPluginData("steamfriends", "apikey", "");
        root.steamId = PluginService.loadPluginData("steamfriends", "steamid", "");
        root.showFriendsOnlineText = PluginService.loadPluginData("steamfriends", "showFriendsOnlineText", true);
        root.onlyShowOnline = PluginService.loadPluginData("steamfriends", "onlyShowOnline", false);
        root.groupOnlineOffline = PluginService.loadPluginData("steamfriends", "groupOnlineOffline", false);
        root.timeFormat = PluginService.loadPluginData("steamfriends", "timeFormat", "system");
        root.showLastOnline = PluginService.loadPluginData("steamfriends", "showLastOnline", true);
        root.sortOrder = PluginService.loadPluginData("steamfriends", "sortOrder", 1);
        root.alphaSortAscending = PluginService.loadPluginData("steamfriends", "alphaSortAscending", true);
        root.statusSortAscending = PluginService.loadPluginData("steamfriends", "statusSortAscending", true);
        root.updateSortedList();
    }

    property bool sortDropdownVisible: false
    property string toastText: ""

    function showToast(msg) {
        toastText = msg;
        toastTimer.restart();
    }

    Timer {
        id: toastTimer
        interval: 1800
    }

    Timer {
        id: refreshSpinTimer
        interval: 1000
        onTriggered: root.isRefreshing = false
    }

    function getEffectiveTimeFormat() {
        if (root.timeFormat === "12h") return "12h";
        if (root.timeFormat === "24h") return "24h";
        
        // System Default mode: check DMS global clock settings, fallback to locale
        let dmsClock24 = PluginService.loadPluginData("dankbar", "use24HourClock", undefined);
        if (dmsClock24 === undefined) {
            dmsClock24 = PluginService.loadPluginData("settings", "use24Hour", undefined);
        }
        if (dmsClock24 !== undefined) {
            return dmsClock24 ? "24h" : "12h";
        }
        
        let sysFmt = Qt.locale().timeFormat(Locale.ShortFormat);
        let is24 = sysFmt.indexOf("H") !== -1 || sysFmt.indexOf("k") !== -1;
        return is24 ? "24h" : "12h";
    }

    function formatHeaderTime(dateObj) {
        if (!dateObj) return "";
        let effFormat = getEffectiveTimeFormat();
        if (effFormat === "24h") {
            return Qt.formatTime(dateObj, "HH:mm");
        } else {
            return Qt.formatTime(dateObj, "h:mm AP");
        }
    }

    function formatLastOnline(lastlogoff) {
        if (!lastlogoff || lastlogoff <= 0) return "Offline";
        let now = Math.floor(Date.now() / 1000);
        let diff = now - lastlogoff;
        if (diff < 60) {
            return "Last online just now";
        } else if (diff < 3600) {
            let mins = Math.floor(diff / 60);
            return "Last online " + mins + (mins === 1 ? " min ago" : " mins ago");
        } else if (diff < 86400) {
            let hours = Math.floor(diff / 3600);
            return "Last online " + hours + (hours === 1 ? " hour ago" : " hours ago");
        } else if (diff < 604800) {
            let days = Math.floor(diff / 86400);
            return "Last online " + days + (days === 1 ? " day ago" : " days ago");
        } else {
            let dateObj = new Date(lastlogoff * 1000);
            let effFormat = getEffectiveTimeFormat();
            let timeStr = (effFormat === "24h") ? Qt.formatDateTime(dateObj, "MMM d, HH:mm") : Qt.formatDateTime(dateObj, "MMM d, h:mm AP");
            return "Last online " + timeStr;
        }
    }

    function refreshFetcher() {
        root.isRefreshing = true;
        refreshSpinTimer.restart();
        friendFetcher.running = false;
        friendFetcher.running = Qt.binding(function() { return root.apiKey !== "" && root.steamId !== ""; });
        root.showToast("Refreshed Friends List");
    }
    
    function updateSortedList() {
        let raw = JSON.parse(JSON.stringify(root.friendsList || []));
        
        raw.forEach(f => {
            f.statusGroup = f.status === "Offline" ? "Offline Friends" : "Online Friends";
        });

        let filtered = raw;
        if (root.onlyShowOnline) {
            filtered = raw.filter(f => f.status !== "Offline");
        }

        let isAsc = root.effectiveSortAscending;
        
        filtered.sort((a, b) => {
            if (root.groupOnlineOffline && a.statusGroup !== b.statusGroup) {
                return a.statusGroup === "Online Friends" ? -1 : 1;
            }

            if (root.sortOrder === 0) {
                return isAsc ? a.name.localeCompare(b.name) : b.name.localeCompare(a.name);
            } else {
                const statusOrder = {
                    "Playing": 0,
                    "Online": 1,
                    "Away": 2,
                    "Busy": 3,
                    "Snooze": 4,
                    "Looking to Play": 5,
                    "Looking to Trade": 6,
                    "Offline": 7
                };
                let aOrder = statusOrder[a.status] ?? 999;
                let bOrder = statusOrder[b.status] ?? 999;
                if (aOrder !== bOrder) {
                    return isAsc ? (aOrder - bOrder) : (bOrder - aOrder);
                }
                if (a.status === "Playing" && b.status === "Playing") {
                    let gameOrder = (a.game || "").localeCompare(b.game || "");
                    if (gameOrder !== 0) return isAsc ? gameOrder : -gameOrder;
                }
                return isAsc ? a.name.localeCompare(b.name) : b.name.localeCompare(a.name);
            }
        });
        
        root.sortedFriendsList = filtered;

        // Build separate group models for distinct visual containers
        let groupsMap = [];
        if (root.groupOnlineOffline) {
            let onlineList = filtered.filter(f => f.statusGroup === "Online Friends");
            let offlineList = filtered.filter(f => f.statusGroup === "Offline Friends");
            
            // Always show Online Friends group
            groupsMap.push({ title: "Online Friends", icon: "person", items: onlineList, gameid: "", emptyMsg: "No friends online", emptyIcon: "group_off" });
            
            // Always show Offline Friends group (unless setting onlyShowOnline is active)
            if (!root.onlyShowOnline) {
                groupsMap.push({ title: "Offline Friends", icon: "person_off", items: offlineList, gameid: "", emptyMsg: "No friends offline", emptyIcon: "person_off" });
            }
        } else if (root.sortOrder === 1) {
            let map = {};
            let orderKeys = [];
            filtered.forEach(f => {
                let key = f.game && f.game.length > 0 ? f.game : "Friends";
                if (!map[key]) {
                    map[key] = { title: key, icon: f.game ? "sports_esports" : "person", items: [], gameid: f.gameid || "", emptyMsg: "", emptyIcon: "group_off" };
                    orderKeys.push(key);
                }
                map[key].items.push(f);
            });
            orderKeys.forEach(k => groupsMap.push(map[k]));
        } else {
            groupsMap.push({ title: "", icon: "", items: filtered, gameid: "", emptyMsg: "", emptyIcon: "" });
        }

        root.friendGroups = [];
        root.friendGroups = groupsMap;
    }

    onFriendsListChanged: updateSortedList()
    onSortOrderChanged: updateSortedList()
    onAlphaSortAscendingChanged: updateSortedList()
    onStatusSortAscendingChanged: updateSortedList()

    // Steam Friends Fetcher Process
    Process {
        id: friendFetcher
        command: ["sh", root.scriptPath, root.apiKey, root.steamId, "json"]
        running: root.apiKey !== "" && root.steamId !== ""

        stdout: SplitParser {
            onRead: data => {
                let output = data.trim();
                try {
                    let json = JSON.parse(output);
                    if (json.error) {
                        root.errorMessage = json.error;
                    } else {
                        root.errorMessage = "";
                        root.friendCount = json.friendCount ? json.friendCount.toString() : "0";
                        root.friendsList = json.friends || [];
                        root.updateSortedList();
                        root.lastUpdated = new Date();
                    }
                } catch (e) {
                    root.errorMessage = "Failed to parse Steam response";
                }
            }
        }
    }

    Timer {
        interval: 300000 
        running: true
        repeat: true
        onTriggered: root.refreshFetcher()
    }

    // Vertical Bar Pill
    verticalBarPill: Component {
        Column {
            id: verticalPillColumn
            spacing: Theme.spacingS

            DankIcon {
                name: "group"
                color: Theme.widgetIconColor || Theme.primary
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.friendCount
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // Horizontal Bar Pill
    horizontalBarPill: Component {
        Row {
            id: horizontalPillRow
            spacing: Theme.spacingXS

            DankIcon {
                name: "group"
                color: Theme.widgetIconColor || Theme.primary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.showFriendsOnlineText ? (root.friendCount + " Friends Online") : root.friendCount
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Popout Content
    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn
            headerText: ""
            showCloseButton: false

            Component.onCompleted: root.sortDropdownVisible = false
            Component.onDestruction: root.sortDropdownVisible = false

            Item {
                id: popoutWrapper
                width: parent.width
                height: mainCol.implicitHeight

                Component.onCompleted: root.sortDropdownVisible = false
                Component.onDestruction: root.sortDropdownVisible = false

                Column {
                    id: mainCol
                    width: parent.width
                    spacing: Theme.spacingM
                    topPadding: 0
                    bottomPadding: 2

                    // Header Card
                    StyledRect {
                        width: parent.width
                        height: 72
                        radius: Theme.cornerRadius * 1.5
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                        // Left: Logo + Title
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingM

                            Rectangle {
                                width: 42
                                height: 42
                                radius: 21
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                                DankIcon {
                                    name: "group"
                                    size: 22
                                    color: Theme.primary
                                    anchors.centerIn: parent
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    text: "Steam Friends"
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeLarge
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    text: root.lastUpdated ? (root.friendCount + " Friends Online • Updated " + root.formatHeaderTime(root.lastUpdated)) : (root.friendCount + " Friends Online")
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    color: Theme.primary
                                    opacity: 0.8
                                }
                            }
                        }

                        // Right: Grouped Single-Icon Action Buttons
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            // Sort Button
                            Rectangle {
                                id: headerSortBtn
                                property bool isHovered: sortMa.containsMouse
                                property bool isActive: root.sortDropdownVisible

                                width: 38
                                height: 38

                                color: isActive ? Theme.withAlpha(Theme.secondary, 0.2) : (isHovered ? Theme.withAlpha(Theme.secondary, 0.12) : Theme.withAlpha(Theme.surfaceContainer, 0.4))
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.secondary, isActive || isHovered ? 0.4 : 0.15)

                                topLeftRadius: isHovered || isActive ? (height / 2) : Theme.cornerRadius
                                bottomLeftRadius: isHovered || isActive ? (height / 2) : Theme.cornerRadius
                                topRightRadius: isHovered || isActive ? (height / 2) : 4
                                bottomRightRadius: isHovered || isActive ? (height / 2) : 4

                                Behavior on topLeftRadius { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                Behavior on bottomLeftRadius { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                Behavior on topRightRadius { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                Behavior on bottomRightRadius { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                scale: sortMa.pressed ? 0.92 : (isHovered ? 1.05 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                DankRipple { id: sortRip; anchors.fill: parent; cornerRadius: parent.topLeftRadius; rippleColor: Theme.secondary }

                                DankIcon {
                                    id: sortIcon
                                    name: root.sortOrder === 1 ? "leaderboard" : "sort_by_alpha"
                                    size: 20
                                    color: Theme.secondary
                                    anchors.centerIn: parent
                                    rotation: root.sortOrder === 1 ? 0 : 360
                                    Behavior on rotation { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                                }

                                MouseArea {
                                    id: sortMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (m) => sortRip.trigger(m.x, m.y)
                                    onClicked: root.sortDropdownVisible = !root.sortDropdownVisible
                                }
                            }

                            // Refresh Button
                            Rectangle {
                                id: headerRefreshBtn
                                property bool isHovered: refreshMa.containsMouse

                                width: 38
                                height: 38

                                color: isHovered ? Theme.withAlpha(Theme.primary, 0.15) : Theme.withAlpha(Theme.surfaceContainer, 0.4)
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.primary, isHovered ? 0.3 : 0.15)

                                topLeftRadius: isHovered || root.isRefreshing ? (height / 2) : 4
                                bottomLeftRadius: isHovered || root.isRefreshing ? (height / 2) : 4
                                topRightRadius: isHovered || root.isRefreshing ? (height / 2) : Theme.cornerRadius
                                bottomRightRadius: isHovered || root.isRefreshing ? (height / 2) : Theme.cornerRadius

                                Behavior on topLeftRadius { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                Behavior on bottomLeftRadius { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                Behavior on topRightRadius { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                Behavior on bottomRightRadius { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                scale: refreshMa.pressed ? 0.92 : (isHovered ? 1.05 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                DankRipple { id: refreshRip; anchors.fill: parent; cornerRadius: parent.topRightRadius; rippleColor: Theme.primary }

                                DankSpinner {
                                    size: 20
                                    color: Theme.primary
                                    anchors.centerIn: parent
                                    visible: root.isRefreshing
                                }

                                DankIcon {
                                    id: refreshBtnIcon
                                    name: "refresh"
                                    size: 20
                                    color: Theme.primary
                                    anchors.centerIn: parent
                                    visible: !root.isRefreshing

                                    rotation: refreshMa.containsMouse ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                }

                                MouseArea {
                                    id: refreshMa
                                    anchors.fill: parent
                                    hoverEnabled: !root.isRefreshing
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (m) => refreshRip.trigger(m.x, m.y)
                                    onClicked: root.refreshFetcher()
                                }
                            }
                        }
                    }

                    // --- Sort Options: Grouped Pair of Container Cards with Dynamic Morphing Corners ---
                    Column {
                        width: parent.width
                        spacing: 2
                        visible: root.sortDropdownVisible

                        // Container 1: SORT BY (Top of Grouped Pair)
                        StyledRect {
                            width: parent.width
                            height: Math.max(0, sortByCol.implicitHeight + Theme.spacingM * 2)
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                            border.width: 1
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                            topLeftRadius: Theme.cornerRadius * 1.2
                            topRightRadius: Theme.cornerRadius * 1.2
                            bottomLeftRadius: 4
                            bottomRightRadius: 4

                            Column {
                                id: sortByCol
                                width: parent.width
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                RowLayout {
                                    spacing: Theme.spacingXS
                                    DankIcon { name: "tune"; size: 14; color: Theme.surfaceText; Layout.alignment: Qt.AlignVCenter }
                                    StyledText {
                                        text: "Sort By"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Bold
                                        color: Theme.surfaceText
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 2

                                    Repeater {
                                        model: [
                                            { title: "Status & Game", icon: "leaderboard", mode: 1 },
                                            { title: "Alphabetical", icon: "sort_by_alpha", mode: 0 }
                                        ]

                                        delegate: Item {
                                            id: sortModeItem
                                            width: parent.width
                                            height: 42

                                            property bool isSelected: root.sortOrder === modelData.mode
                                            property bool isHovered: sortModeMa.containsMouse

                                            Shape {
                                                id: sortModeBg
                                                anchors.fill: parent

                                                property real innerRadius: 4
                                                property real outerRadius: Theme.cornerRadius || 12
                                                property bool isFirst: index === 0
                                                property bool isLast: index === 1

                                                property real tlr: (isSelected || isHovered) ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                property real trr: (isSelected || isHovered) ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                property real blr: (isSelected || isHovered) ? (height / 2) : (isLast ? outerRadius : innerRadius)
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
                                                    fillColor: sortModeBg.paintColor
                                                    strokeColor: sortModeBg.paintBorder
                                                    strokeWidth: 1

                                                    startX: sortModeBg.tlrAnim; startY: 0
                                                    PathLine { x: sortModeBg.width - sortModeBg.trrAnim; y: 0 }
                                                    PathArc { x: sortModeBg.width; y: sortModeBg.trrAnim; radiusX: sortModeBg.trrAnim; radiusY: sortModeBg.trrAnim; direction: PathArc.Clockwise }
                                                    PathLine { x: sortModeBg.width; y: sortModeBg.height - sortModeBg.brrAnim }
                                                    PathArc { x: sortModeBg.width - sortModeBg.brrAnim; y: sortModeBg.height; radiusX: sortModeBg.brrAnim; radiusY: sortModeBg.brrAnim; direction: PathArc.Clockwise }
                                                    PathLine { x: sortModeBg.blrAnim; y: sortModeBg.height }
                                                    PathArc { x: 0; y: sortModeBg.height - sortModeBg.blrAnim; radiusX: sortModeBg.blrAnim; radiusY: sortModeBg.blrAnim; direction: PathArc.Clockwise }
                                                    PathLine { x: 0; y: sortModeBg.tlrAnim }
                                                    PathArc { x: sortModeBg.tlrAnim; y: 0; radiusX: sortModeBg.tlrAnim; radiusY: sortModeBg.tlrAnim; direction: PathArc.Clockwise }
                                                }
                                            }

                                            scale: sortModeMa.pressed ? 0.98 : (isHovered ? 1.01 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                            DankRipple { id: sortModeRip; anchors.fill: parent; cornerRadius: sortModeBg.tlrAnim; rippleColor: Theme.primary }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.spacingM
                                                anchors.rightMargin: Theme.spacingM
                                                spacing: Theme.spacingM

                                                DankIcon {
                                                    name: modelData.icon
                                                    size: 20
                                                    color: sortModeItem.isSelected ? Theme.primary : Theme.surfaceVariantText
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                StyledText {
                                                    text: modelData.title
                                                    font.pixelSize: Theme.fontSizeMedium
                                                    font.weight: sortModeItem.isSelected ? Font.Medium : Font.Normal
                                                    color: Theme.surfaceText
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                DankIcon {
                                                    name: "check"
                                                    size: 18
                                                    color: Theme.primary
                                                    visible: sortModeItem.isSelected
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }

                                            MouseArea {
                                                id: sortModeMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onPressed: (m) => sortModeRip.trigger(m.x, m.y)
                                                onClicked: {
                                                    root.sortOrder = modelData.mode;
                                                    PluginService.savePluginData("steamfriends", "sortOrder", root.sortOrder);
                                                    PluginService.setGlobalVar("steamfriends", "sortOrder", root.sortOrder);
                                                    root.updateSortedList();
                                                    root.showToast("Sorted by " + modelData.title);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Container 2: SORT DIRECTION (Bottom of Grouped Pair)
                        StyledRect {
                            width: parent.width
                            height: Math.max(0, sortDirCol.implicitHeight + Theme.spacingM * 2)
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                            border.width: 1
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                            topLeftRadius: 4
                            topRightRadius: 4
                            bottomLeftRadius: Theme.cornerRadius * 1.2
                            bottomRightRadius: Theme.cornerRadius * 1.2

                            Column {
                                id: sortDirCol
                                width: parent.width
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                RowLayout {
                                    spacing: Theme.spacingXS
                                    DankIcon { name: "swap_vert"; size: 14; color: Theme.surfaceText; Layout.alignment: Qt.AlignVCenter }
                                    StyledText {
                                        text: "Sort Direction"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Bold
                                        color: Theme.surfaceText
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 2

                                    Repeater {
                                        model: [
                                            { title: "Ascending", icon: "arrow_upward", dir: true },
                                            { title: "Descending", icon: "arrow_downward", dir: false }
                                        ]

                                        delegate: Item {
                                            id: sortDirItem
                                            width: parent.width
                                            height: 42

                                            property bool isSelected: root.effectiveSortAscending === modelData.dir
                                            property bool isHovered: sortDirMa.containsMouse

                                            Shape {
                                                id: sortDirBg
                                                anchors.fill: parent

                                                property real innerRadius: 4
                                                property real outerRadius: Theme.cornerRadius || 12
                                                property bool isFirst: index === 0
                                                property bool isLast: index === 1

                                                property real tlr: (isSelected || isHovered) ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                property real trr: (isSelected || isHovered) ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                property real blr: (isSelected || isHovered) ? (height / 2) : (isLast ? outerRadius : innerRadius)
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
                                                    fillColor: sortDirBg.paintColor
                                                    strokeColor: sortDirBg.paintBorder
                                                    strokeWidth: 1

                                                    startX: sortDirBg.tlrAnim; startY: 0
                                                    PathLine { x: sortDirBg.width - sortDirBg.trrAnim; y: 0 }
                                                    PathArc { x: sortDirBg.width; y: sortDirBg.trrAnim; radiusX: sortDirBg.trrAnim; radiusY: sortDirBg.trrAnim; direction: PathArc.Clockwise }
                                                    PathLine { x: sortDirBg.width; y: sortDirBg.height - sortDirBg.brrAnim }
                                                    PathArc { x: sortDirBg.width - sortDirBg.brrAnim; y: sortDirBg.height; radiusX: sortDirBg.brrAnim; radiusY: sortDirBg.brrAnim; direction: PathArc.Clockwise }
                                                    PathLine { x: sortDirBg.blrAnim; y: sortDirBg.height }
                                                    PathArc { x: 0; y: sortDirBg.height - sortDirBg.blrAnim; radiusX: sortDirBg.blrAnim; radiusY: sortDirBg.blrAnim; direction: PathArc.Clockwise }
                                                    PathLine { x: 0; y: sortDirBg.tlrAnim }
                                                    PathArc { x: sortDirBg.tlrAnim; y: 0; radiusX: sortDirBg.tlrAnim; radiusY: sortDirBg.tlrAnim; direction: PathArc.Clockwise }
                                                }
                                            }

                                            scale: sortDirMa.pressed ? 0.98 : (isHovered ? 1.01 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                            DankRipple { id: sortDirRip; anchors.fill: parent; cornerRadius: sortDirBg.tlrAnim; rippleColor: Theme.primary }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.spacingM
                                                anchors.rightMargin: Theme.spacingM
                                                spacing: Theme.spacingM

                                                DankIcon {
                                                    name: modelData.icon
                                                    size: 20
                                                    color: sortDirItem.isSelected ? Theme.primary : Theme.surfaceVariantText
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                StyledText {
                                                    text: modelData.title
                                                    font.pixelSize: Theme.fontSizeMedium
                                                    font.weight: sortDirItem.isSelected ? Font.Medium : Font.Normal
                                                    color: Theme.surfaceText
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                DankIcon {
                                                    name: "check"
                                                    size: 18
                                                    color: Theme.primary
                                                    visible: sortDirItem.isSelected
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }

                                            MouseArea {
                                                id: sortDirMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onPressed: (m) => sortDirRip.trigger(m.x, m.y)
                                                onClicked: {
                                                    if (root.sortOrder === 0) {
                                                        root.alphaSortAscending = modelData.dir;
                                                        PluginService.savePluginData("steamfriends", "alphaSortAscending", root.alphaSortAscending);
                                                        PluginService.setGlobalVar("steamfriends", "alphaSortAscending", root.alphaSortAscending);
                                                    } else {
                                                        root.statusSortAscending = modelData.dir;
                                                        PluginService.savePluginData("steamfriends", "statusSortAscending", root.statusSortAscending);
                                                        PluginService.setGlobalVar("steamfriends", "statusSortAscending", root.statusSortAscending);
                                                    }
                                                    root.updateSortedList();
                                                    root.showToast("Direction set to " + modelData.title);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Error Container (if error present)
                    StyledRect {
                        width: parent.width
                        visible: root.errorMessage.length > 0
                        height: Math.max(0, errText.implicitHeight + Theme.spacingM * 2)
                        radius: Theme.cornerRadius
                        color: Qt.rgba(0.95, 0.26, 0.21, 0.12)
                        border.width: 1
                        border.color: Qt.rgba(0.95, 0.26, 0.21, 0.4)

                        StyledText {
                            id: errText
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: root.errorMessage
                            color: "#F44336"
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    // Empty Fallback Container (No friends found at all)
                    StyledRect {
                        width: parent.width
                        height: 72
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        visible: root.friendsList.length === 0

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankIcon {
                                name: root.apiKey === "" || root.steamId === "" ? "settings" : "group_off"
                                size: 20
                                color: Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                text: root.apiKey === "" || root.steamId === "" ? "Please configure API Key and Steam ID in settings." : "No friends online"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeMedium
                                Layout.alignment: Qt.AlignVCenter
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // Separate Container Cards for Each Group of Friends
                    Repeater {
                        model: root.friendGroups
                        visible: root.friendsList.length > 0

                        delegate: StyledRect {
                            id: groupCard
                            width: parent.width
                            height: Math.max(0, groupCol.implicitHeight + Theme.spacingM * 2)
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                            border.width: 1
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                            Column {
                                id: groupCol
                                width: parent.width
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                // Section Header Format (Shown ONLY when grouping is active)
                                RowLayout {
                                    id: groupHeaderRow
                                    visible: modelData.title !== undefined && modelData.title.length > 0 && (root.groupOnlineOffline || root.sortOrder === 1)
                                    width: parent.width
                                    spacing: Theme.spacingXS

                                    Image {
                                        width: 43
                                        height: 16
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: modelData.gameid !== undefined && modelData.gameid !== ""
                                        source: modelData.gameid ? ("https://cdn.cloudflare.steamstatic.com/steam/apps/" + modelData.gameid + "/capsule_184x69.jpg") : ""
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        cache: true

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: modelData.gameid !== ""
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Qt.openUrlExternally("https://store.steampowered.com/app/" + modelData.gameid)
                                        }
                                    }

                                    DankIcon {
                                        name: modelData.icon ? modelData.icon : "person"
                                        size: 14
                                        color: Theme.surfaceText
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: !modelData.gameid
                                    }

                                    StyledText {
                                        text: modelData.title || ""
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Bold
                                        color: Theme.surfaceText
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                // Empty Category Container Pill if 0 items in this group
                                StyledRect {
                                    width: parent.width
                                    height: 44
                                    radius: Theme.cornerRadius
                                    color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.05)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.12)
                                    visible: modelData.items.length === 0

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingS

                                        DankIcon {
                                            name: modelData.emptyIcon ? modelData.emptyIcon : "group_off"
                                            size: 18
                                            color: Theme.surfaceVariantText
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        StyledText {
                                            text: modelData.emptyMsg || "No friends in this group"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.surfaceVariantText
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 2
                                    visible: modelData.items.length > 0

                                    Repeater {
                                        model: modelData.items

                                        delegate: Item {
                                            id: friendDelegate
                                            width: parent.width
                                            height: 54

                                            property bool isHovered: friendMa.containsMouse

                                            Shape {
                                                id: friendBg
                                                anchors.fill: parent

                                                property real innerRadius: 6
                                                property real outerRadius: Theme.cornerRadius || 12
                                                property bool isFirst: index === 0
                                                property bool isLast: index === modelData.items.length - 1

                                                property real tlr: isHovered ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                property real trr: isHovered ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                property real blr: isHovered ? (height / 2) : (isLast ? outerRadius : innerRadius)
                                                property real brr: isHovered ? (height / 2) : (isLast ? outerRadius : innerRadius)

                                                property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                                                property color paintColor: isHovered
                                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                                        : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)

                                                property color paintBorder: isHovered
                                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                                        : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                                                ShapePath {
                                                    fillColor: friendBg.paintColor
                                                    strokeColor: friendBg.paintBorder
                                                    strokeWidth: 1

                                                    startX: friendBg.tlrAnim; startY: 0
                                                    PathLine { x: friendBg.width - friendBg.trrAnim; y: 0 }
                                                    PathArc { x: friendBg.width; y: friendBg.trrAnim; radiusX: friendBg.trrAnim; radiusY: friendBg.trrAnim; direction: PathArc.Clockwise }
                                                    PathLine { x: friendBg.width; y: friendBg.height - friendBg.brrAnim }
                                                    PathArc { x: friendBg.width - friendBg.brrAnim; y: friendBg.height; radiusX: friendBg.brrAnim; radiusY: friendBg.brrAnim; direction: PathArc.Clockwise }
                                                    PathLine { x: friendBg.blrAnim; y: friendBg.height }
                                                    PathArc { x: 0; y: friendBg.height - friendBg.blrAnim; radiusX: friendBg.blrAnim; radiusY: friendBg.blrAnim; direction: PathArc.Clockwise }
                                                    PathLine { x: 0; y: friendBg.tlrAnim }
                                                    PathArc { x: friendBg.tlrAnim; y: 0; radiusX: friendBg.tlrAnim; radiusY: friendBg.tlrAnim; direction: PathArc.Clockwise }
                                                }
                                            }

                                            scale: friendMa.pressed ? 0.98 : (isHovered ? 1.01 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                            DankRipple {
                                                id: friendRip
                                                anchors.fill: parent
                                                cornerRadius: friendBg.tlrAnim
                                                rippleColor: Theme.primary
                                            }

                                            RowLayout {
                                                id: friendRow
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.spacingM
                                                anchors.rightMargin: Theme.spacingM
                                                spacing: Theme.spacingM

                                                DankCircularImage {
                                                    width: 36
                                                    height: 36
                                                    Layout.alignment: Qt.AlignVCenter
                                                    imageSource: modelData.avatarUrl || ""
                                                    fallbackIcon: "person"
                                                    cacheImages: true
                                                }

                                                Column {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    spacing: 1

                                                    StyledText {
                                                        width: parent.width
                                                        text: modelData.name
                                                        font.pixelSize: Theme.fontSizeMedium
                                                        font.weight: Font.Medium
                                                        color: Theme.surfaceText
                                                        elide: Text.ElideRight
                                                    }

                                                    StyledText {
                                                        width: parent.width
                                                        text: modelData.game && modelData.game.length > 0 ? ("Playing: " + modelData.game) :
                                                              (modelData.status === "Offline" && root.showLastOnline ? root.formatLastOnline(modelData.lastlogoff) : modelData.status)
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        color: isHovered ? Theme.primary : Theme.surfaceVariantText
                                                        elide: Text.ElideRight
                                                        visible: text.length > 0
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                }

                                                DankIcon {
                                                    name: "chat"
                                                    size: 16
                                                    color: Theme.surfaceVariantText
                                                    opacity: isHovered ? 0.9 : 0.0
                                                    Layout.alignment: Qt.AlignVCenter
                                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                                }

                                                // Status Dot
                                                Rectangle {
                                                    width: 8
                                                    height: 8
                                                    radius: 4
                                                    Layout.alignment: Qt.AlignVCenter
                                                    color: modelData.status === "Playing" ? Theme.primary :
                                                           modelData.status === "Online" ? "#4CAF50" :
                                                           modelData.status === "Away" ? "#FFC107" :
                                                           modelData.status === "Busy" ? "#F44336" :
                                                           modelData.status === "Snooze" ? "#9E9E9E" :
                                                           modelData.status === "Looking to Trade" ? "#26A69A" :
                                                           modelData.status === "Looking to Play" ? "#2196F3" :
                                                           modelData.status === "Offline" ? "#616161" : "#9C27B0"
                                                }
                                            }

                                            MouseArea {
                                                id: friendMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onPressed: (m) => friendRip.trigger(m.x, m.y)
                                                onClicked: {
                                                    if (modelData.steamid) {
                                                        Qt.openUrlExternally("steam://friends/message/" + modelData.steamid)
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

                // Dynamic Toast Notification Overlay
                Rectangle {
                    id: toastPill
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spacingS
                    height: 32
                    width: toastLayout.implicitWidth + Theme.spacingM * 2
                    radius: height / 2
                    color: Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.95)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                    border.width: 1
                    z: 999
                    opacity: toastTimer.running ? 1.0 : 0.0
                    scale: toastTimer.running ? 1.0 : 0.75

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    RowLayout {
                        id: toastLayout
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "info"
                            size: 16
                            color: Theme.primary
                        }

                        StyledText {
                            text: root.toastText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }
                    }
                }
            }
        }
    }
}
