import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {

    id: root

    // This variable stores the count and friend list
    property string friendCount: "0"

    // This variable stores the raw friend list from the script, it will be sorted and stored in sortedFriendsList
    property var friendsList: []
    
    // This variable stores the sorted friend list that is used for display, it is updated whenever friendsList changes or when the sort order changes
    property var sortedFriendsList: []

    // This variable stores the last error reported by the fetch script, empty string means no error
    property string errorMessage: ""

    // This variable stores the timestamp of the last successful friend list fetch, null means never
    property var lastUpdated: null

    // Absolute path to the fetch script, which lives alongside this file
    property string scriptPath: decodeURIComponent(Qt.resolvedUrl("steam_friends.sh").toString().replace("file://", ""))
    
    // Load API key from saved settings
    property string apiKey: pluginService ? pluginService.loadPluginData("steamfriends", "apikey", ""): ""
    property string steamId: pluginService ? pluginService.loadPluginData("steamfriends", "steamid", "") : ""

    // Whether the horizontal bar pill shows "X Friends Online" or just the count
    property bool showFriendsOnlineText: pluginService ? pluginService.loadPluginData("steamfriends", "showFriendsOnlineText", true) : true

    // Hide the bar pill while no friends are online
    property bool hideWhenEmpty: pluginService ? pluginService.loadPluginData("steamfriends", "hideWhenEmpty", false) : false

    // Desktop notifications for friends coming online / starting a game
    property bool notifyOnline: pluginService ? pluginService.loadPluginData("steamfriends", "notifyOnline", false) : false
    property bool notifyGame: pluginService ? pluginService.loadPluginData("steamfriends", "notifyGame", false) : false

    // How often the friend list is refreshed, in minutes
    property int refreshMinutes: pluginService ? parseInt(pluginService.loadPluginData("steamfriends", "refreshMinutes", "5")) || 5 : 5

    // Whether both the API key and Steam ID have been entered in settings
    readonly property bool isConfigured: apiKey !== "" && steamId !== ""

    // "X Friend(s) Online" label used in the bar pill and popout header
    readonly property string friendsOnlineLabel: friendCount + (friendCount === "1" ? " Friend Online" : " Friends Online")

    // React when settings change
    Connections {
        target: pluginService
        // DMS only says which plugin changed, not which key, so reload every setting and refresh if the credentials changed
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== "steamfriends") return
            const newApiKey = pluginService.loadPluginData("steamfriends", "apikey", "")
            const newSteamId = pluginService.loadPluginData("steamfriends", "steamid", "")
            if (newApiKey !== apiKey || newSteamId !== steamId) {
                // A different account means a different friend list, so don't notify about it
                knownFriends = null
                apiKey = newApiKey
                steamId = newSteamId
                settingsRefreshTimer.restart()
            }
            showFriendsOnlineText = pluginService.loadPluginData("steamfriends", "showFriendsOnlineText", true)
            hideWhenEmpty = pluginService.loadPluginData("steamfriends", "hideWhenEmpty", false)
            notifyOnline = pluginService.loadPluginData("steamfriends", "notifyOnline", false)
            notifyGame = pluginService.loadPluginData("steamfriends", "notifyGame", false)
            refreshMinutes = parseInt(pluginService.loadPluginData("steamfriends", "refreshMinutes", "5")) || 5
        }
    }

    // Waits for the settings to stop changing before refreshing, so typing a key doesn't fire a request per keystroke
    Timer {
        id: settingsRefreshTimer
        interval: 1000
        onTriggered: root.refresh()
    }

    // Clear stale friends once the credentials are removed, so the setup prompt shows
    onIsConfiguredChanged: {
        if (!isConfigured) {
            clearFriends()
            errorMessage = ""
        }
    }

    // Empties the friend list and count, used when a fetch fails so stale data isn't shown alongside the error
    function clearFriends() {
        root.friendCount = "0"
        root.friendsList = []
    }

    // Text typed in the popout's search box, cleared when the popout closes
    property string searchText: ""

    // The sorted list filtered by the search box, matching on name or game. This is what the popout shows
    readonly property var displayedFriendsList: {
        const query = searchText.trim().toLowerCase()
        if (query === "") return sortedFriendsList
        return sortedFriendsList.filter(f => f.name.toLowerCase().includes(query) || (f.game || "").toLowerCase().includes(query))
    }

    // Short summary for the bar tooltip, e.g. "2 playing · 3 online"
    readonly property string statusSummary: {
        if (!isConfigured) return "Steam Friends: not set up"
        if (errorMessage !== "") return "Steam Friends: " + errorMessage
        const playing = friendsList.filter(f => f.status === "Playing").length
        const others = friendsList.length - playing
        if (friendsList.length === 0) return "No friends online"
        let parts = []
        if (playing > 0) parts.push(playing + " playing")
        if (others > 0) parts.push(others + " online")
        return parts.join(" · ")
    }

    // Hide the pill when the option is on and nobody is online. It stays visible while unconfigured or erroring so the problem can be seen
    readonly property bool shouldHidePill: hideWhenEmpty && isConfigured && errorMessage === "" && friendsList.length === 0
    onShouldHidePillChanged: shouldHidePill ? setVisibilityOverride(false) : clearVisibilityOverride()
    Component.onCompleted: if (shouldHidePill) setVisibilityOverride(false)

    // Friends seen in the last successful fetch, keyed by steamid, used to work out who just came online or started a game.
    // null until the first fetch, so friends already online at startup don't trigger notifications
    property var knownFriends: null

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Steam Friends", "-i", "steam", title, body])
    }

    // Compares a new friend list against the last one and sends notifications for the changes the user opted into
    function checkForNotifications(newFriends) {
        const previous = knownFriends
        let current = {}
        for (const f of newFriends) current[f.steamid] = f
        knownFriends = current
        if (previous === null || (!notifyOnline && !notifyGame)) return

        let cameOnline = []
        let startedGame = []
        for (const f of newFriends) {
            const before = previous[f.steamid]
            if (!before) {
                if (notifyOnline) cameOnline.push(f)
                else if (notifyGame && f.game) startedGame.push(f)
            } else if (notifyGame && f.game && f.game !== before.game) {
                startedGame.push(f)
            }
        }

        // Several at once (e.g. after waking from sleep) are rolled into one notification instead of a flood
        if (cameOnline.length > 3) {
            notify(cameOnline.length + " friends came online", cameOnline.map(f => f.name).join(", "))
        } else {
            for (const f of cameOnline) notify(f.name + " is now online", f.game ? "Playing " + f.game : f.status)
        }
        if (startedGame.length > 3) {
            notify(startedGame.length + " friends started playing", startedGame.map(f => f.name + ": " + f.game).join("\n"))
        } else {
            for (const f of startedGame) notify(f.name + " is playing", f.game)
        }
    }

    // Bar tooltip window, created on first hover
    Loader {
        id: barTooltipLoader
        active: false
        sourceComponent: DTooltip {}
    }

    // Shows the status summary next to a bar pill, positioned the same way DMS positions its own bar tooltips
    function showBarTooltip(item) {
        if (!root.parentScreen || root.interactionActive) return
        barTooltipLoader.active = true
        if (!barTooltipLoader.item) return
        const screen = root.parentScreen
        const edge = root.axis?.edge ?? "top"
        if (root.isVertical) {
            const pos = item.mapToItem(null, item.width / 2, item.height / 2)
            const isLeft = edge === "left"
            const x = isLeft ? (root.barThickness + root.barSpacing + Theme.spacingXS) : (screen.width - root.barThickness - root.barSpacing - Theme.spacingXS)
            barTooltipLoader.item.show(root.statusSummary, x, pos.y, screen, isLeft, !isLeft)
        } else {
            const pos = item.mapToItem(null, item.width / 2, 0)
            let y
            if (edge === "bottom") {
                const tooltipHeight = Theme.fontSizeSmall * 1.5 + Theme.spacingS * 2
                y = screen.height - root.barThickness - root.barSpacing - Theme.spacingXS - tooltipHeight
            } else {
                y = root.barThickness + root.barSpacing + Theme.spacingXS
            }
            barTooltipLoader.item.show(root.statusSummary, pos.x, y, screen, false, false)
        }
    }

    function hideBarTooltip() {
        if (barTooltipLoader.item) barTooltipLoader.item.hide()
    }

    // Hide the tooltip as soon as the popout opens, and clear the search when it closes
    onInteractionActiveChanged: {
        if (interactionActive) hideBarTooltip()
        else searchText = ""
    }

    // This variable determines the sorting order of the friend list, it can be toggled by the user, and it will determine how the friend list is sorted (0 = alphabetical, 1 = status)
    // Saved so the choice survives a restart
    property int sortOrder: pluginService ? pluginService.loadPluginData("steamfriends", "sortOrder", 1) : 1 // 0 = alphabetical, 1 = status
    
    function updateSortedList() {
        let sorted = JSON.parse(JSON.stringify(root.friendsList))
        
        if (root.sortOrder === 0) {
            // Sort alphabetically by name
            sorted.sort((a, b) => a.name.localeCompare(b.name))
        } else {
            // Sort by status, most available first
            const statusOrder = {"Playing": 0, "Online": 1, "Looking to Play": 2, "Looking to Trade": 3, "Busy": 4, "Away": 5, "Snooze": 6}
            sorted.sort((a, b) => {
                let aOrder = statusOrder[a.status] ?? 999
                let bOrder = statusOrder[b.status] ?? 999
                if (aOrder !== bOrder) return aOrder - bOrder
                // Group friends playing the same game together
                if (a.status === "Playing" && b.status === "Playing") {
                    let gameOrder = (a.game || "").localeCompare(b.game || "")
                    if (gameOrder !== 0) return gameOrder
                }
                return a.name.localeCompare(b.name)
            })
        }
        
        root.sortedFriendsList = sorted
    }

    // Looks up the Steam appid for a game section header, so its capsule icon can be shown
    function gameIdForSection(sectionName) {
        for (let i = 0; i < root.sortedFriendsList.length; i++) {
            if (root.sortedFriendsList[i].game === sectionName) {
                return root.sortedFriendsList[i].gameid || ""
            }
        }
        return ""
    }

    onFriendsListChanged: updateSortedList()

    // Restarts the fetch process. The running binding is re-applied because the Process sets running = false itself when it exits
    function refresh() {
        friendFetcher.running = false
        friendFetcher.running = Qt.binding(function() { return root.isConfigured })
    }

    // Process --------------------------------------------------------------------------------
    // This process runs the steam_friends.sh script to fetch the friend list and count, it expects a single line of JSON in the format:
    // {"friendCount": 1, "friends": [{"name": "Friend1", "steamid": "7656...", "status": "Playing", "game": "Game1", "gameid": "123", "avatarUrl": "https://..."}]}
    // or {"error": "message"} on failure. Credentials are passed as environment variables so they don't show up in the process list
    Process {
        id: friendFetcher
        command: ["bash", root.scriptPath]
        environment: ({
            "STEAM_API_KEY": root.apiKey,
            "STEAM_ID": root.steamId
        })
        running: root.isConfigured

        stdout: SplitParser {
            onRead: data => {
                let output = data.trim()
                try {
                    let json = JSON.parse(output)
                    if (json.error) {
                        root.errorMessage = json.error
                        root.clearFriends()
                        console.error("(SF) Script reported error:", json.error)
                    } else {
                        root.errorMessage = ""
                        root.friendCount = json.friendCount.toString()
                        root.friendsList = json.friends || []
                        root.updateSortedList()
                        root.checkForNotifications(root.friendsList)
                        root.lastUpdated = new Date()
                    }
                } catch (e) {
                    root.errorMessage = "Failed to parse Steam response"
                    root.clearFriends()
                    console.error("(SF) Error parsing JSON:", e)
                    console.error("(SF) Output was:", output)
                }
            }
        }
    }

    // Timer --------------------------------------------------------------------------------
    // This timer will refresh the friend list every refreshMinutes minutes by restarting the process
    Timer {
        interval: root.refreshMinutes * 60000
        running: true
        repeat: true
        onTriggered: {
            root.refresh()
        }
    }

    // V Pill -------------------------------------------------------------------------------
    // Vertical pill content - This is the content that appears in the vertical bar, it will show an icon with the number of friends online below it
    verticalBarPill: Component {
        Column {
            id: verticalPillColumn
            spacing: Theme.spacingS

            HoverHandler {
                onHoveredChanged: hovered ? root.showBarTooltip(verticalPillColumn) : root.hideBarTooltip()
            }

            DankIcon {
                name: "contacts"
                color: Theme.primary
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

    // H Pill -------------------------------------------------------------------------------
    // Horizontal pill content - This is the content that appears in the horizontal bar, it will show the number of friends online and an icon
    horizontalBarPill: Component {
        Row {
            id: horizontalPillRow
            spacing: Theme.spacingXS

            HoverHandler {
                onHoveredChanged: hovered ? root.showBarTooltip(horizontalPillRow) : root.hideBarTooltip()
            }

            DankIcon {
                name: "group"
                color: Theme.primary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.showFriendsOnlineText ? root.friendsOnlineLabel : root.friendCount
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Row -------------------------------------------------------------------------------
    // This is the popout content that appears when you click the pill, it will show a list of friends with their status and game if they are playing something
    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn
            headerText: root.friendsOnlineLabel
            showCloseButton: true

            Item {
                id: sortRow
                width: parent.width
                height: buttonRow.implicitHeight + Theme.spacingM * 2

                Row {
                    id: buttonRow
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    // Sort button - icon-only, toggles the sorting order between alphabetical and status
                    DankActionButton {
                        iconName: "sort"
                        iconSize: Theme.iconSizeSmall
                        iconColor: Theme.surfaceVariantText
                        tooltipText: "Sort: " + (root.sortOrder === 0 ? "Alphabetical" : "Status")
                        onClicked: {
                            root.sortOrder = (root.sortOrder + 1) % 2
                            root.updateSortedList()
                            if (pluginService) pluginService.savePluginData("steamfriends", "sortOrder", root.sortOrder)
                        }
                    }
                    // Refresh button - icon-only, refreshes the friend list by restarting the process. Spins while a fetch is running
                    DankActionButton {
                        id: refreshButton
                        iconName: "refresh"
                        iconSize: Theme.iconSizeSmall
                        iconColor: friendFetcher.running ? Theme.primary : Theme.surfaceVariantText
                        tooltipText: friendFetcher.running ? "Refreshing..." : "Refresh"
                        onClicked: {
                            root.refresh()
                        }

                        // alwaysRunToEnd finishes the current turn when the fetch ends, so the icon stops upright
                        RotationAnimation on rotation {
                            running: friendFetcher.running
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                        }
                    }
                }

                // Last updated timestamp - shown after the first successful fetch
                StyledText {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.lastUpdated ? "Updated " + Qt.formatTime(root.lastUpdated, "h:mm AP") : ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    opacity: 0.7
                    visible: root.lastUpdated !== null
                }
            }

            // Error banner - shown when the last fetch attempt failed
            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.errorMessage
                color: Theme.error
                visible: root.errorMessage.length > 0
            }

            // Search box - filters the list by friend name or game
            DankTextField {
                width: parent.width - Theme.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                placeholderText: "Search friends or games"
                leftIconName: "search"
                showClearButton: true
                text: root.searchText
                onTextChanged: root.searchText = text
                visible: root.friendsList.length > 0
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM
                padding: Theme.spacingM

                // List of friends - This is the box containing the friend entries, it will scroll if there are many friends
                Rectangle {
                    width: parent.width - Theme.spacingM * 2
                    height: Math.min(friendsListView.contentHeight, 400)
                    
                    clip: true
                    color: "transparent"

                    DankListView {
                        id: friendsListView
                        anchors.fill: parent
                        spacing: Theme.spacingS
                        model: root.displayedFriendsList

                        // Group friends by game when sorted by status (game is "" for non-playing friends, so no header shows for them)
                        section.property: root.sortOrder === 1 ? "game" : ""
                        section.criteria: ViewSection.FullString
                        section.delegate: Component {
                            Item {
                                readonly property bool isTrailingBoundary: section.length === 0
                                    && root.displayedFriendsList.length > 0
                                    && (root.displayedFriendsList[0].game || "") !== ""
                                readonly property string gameId: section.length > 0 ? root.gameIdForSection(section) : ""
                                readonly property string gameIconUrl: gameId !== "" ? ("https://cdn.cloudflare.steamstatic.com/steam/apps/" + gameId + "/capsule_184x69.jpg") : ""

                                width: friendsListView.width
                                height: section.length > 0 ? (Math.max(sectionText.implicitHeight, gameIcon.height) + Theme.spacingS)
                                                            : (isTrailingBoundary ? (1 + Theme.spacingS) : 0)

                                Row {
                                    visible: section.length > 0
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingXS
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS

                                    Image {
                                        id: gameIcon
                                        width: 43
                                        height: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: gameIconUrl !== ""
                                        source: gameIconUrl
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        cache: true
                                    }

                                    StyledText {
                                        id: sectionText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: section
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        color: Theme.primary
                                    }
                                }

                                Rectangle {
                                    visible: isTrailingBoundary
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: 1
                                    color: Theme.outline
                                }

                                // Click a game section header to open its Steam store page
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: gameId !== ""
                                    cursorShape: gameId !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: Qt.openUrlExternally("https://store.steampowered.com/app/" + gameId)
                                }
                            }
                        }

                        // This is each friend entry, it will show the friend's name, status, and game if they are playing something
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: friendRow.implicitHeight + Theme.spacingS * 2
                            // DMS card colour (follows the user's card surface and transparency settings), falling back on older DMS versions
                            color: Theme.nestedSurface ?? Theme.surfaceContainer
                            radius: Theme.cornerRadius

                            // Hover highlight - a translucent layer over the card, so it works with any card colour
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: Theme.surfaceTextHover
                                opacity: friendMouseArea.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }

                            Row {
                                id: friendRow
                                width: parent.width - Theme.spacingM * 2
                                height: parent.height
                                anchors.centerIn: parent
                                spacing: Theme.spacingS

                                // Friend avatar
                                DankCircularImage {
                                    width: 36
                                    height: 36
                                    anchors.verticalCenter: parent.verticalCenter
                                    imageSource: modelData.avatarUrl || ""
                                    fallbackIcon: "person"
                                    cacheImages: true
                                }

                                // Status indicator (colored dot)
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: modelData.status === "Playing" ? Theme.accentColor :
                                           modelData.status === "Online" ? "#4CAF50" :
                                           modelData.status === "Away" ? "#FFC107" :
                                           modelData.status === "Busy" ? "#F44336" :
                                           modelData.status === "Snooze" ? "#9E9E9E" :
                                           modelData.status === "Looking to Trade" ? "#26A69A" :
                                           modelData.status === "Looking to Play" ? "#2196F3" :
                                           modelData.status === "Offline" ? "#616161" : "#9C27B0"
                                }

                                // Friend info - This column contains the friend's name and status/game info, it will be to the right of the status indicator
                                Column {
                                    spacing: 2
                                    anchors.verticalCenter: parent.verticalCenter

                                    // Friend name
                                    StyledText {
                                        text: modelData.name
                                        font.pixelSize: Theme.fontSizeXLarge
                                        color: Theme.primary
                                    }
                                    // Status or game info
                                    StyledText {
                                        text: modelData.game && modelData.game.length > 0 ? 
                                              "Playing: " + modelData.game : 
                                              modelData.status
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                        visible: text.length > 0
                                    }
                                }
                            }

                            // Click a friend to open a chat with them in Steam
                            MouseArea {
                                id: friendMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                // Left click opens a chat, right click opens their Steam profile
                                onClicked: mouse => {
                                    if (!modelData.steamid) return
                                    if (mouse.button === Qt.RightButton) {
                                        Qt.openUrlExternally("steam://url/SteamIDPage/" + modelData.steamid)
                                    } else {
                                        Qt.openUrlExternally("steam://friends/message/" + modelData.steamid)
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty state - prompts for setup if not configured, otherwise shows "No friends online" (hidden while an error is shown)
                StyledText {
                    text: root.isConfigured ? "No friends online" : "Enter your API key and Steam ID in the plugin settings"
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.friendsList.length === 0 && root.errorMessage.length === 0
                }

                // Search found nothing
                StyledText {
                    text: "No friends match \"" + root.searchText.trim() + "\""
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.friendsList.length > 0 && root.displayedFriendsList.length === 0
                }
            }
        }
    }
}
