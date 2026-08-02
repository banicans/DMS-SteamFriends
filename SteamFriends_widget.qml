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

    // This variable stores the current sorting order, it can be toggled by the user, and it will determine how the friend list is sorted (0 = alphabetical, 1 = status)
    property string scriptPath: Qt.resolvedUrl("steam_friends.sh").toString().replace("file://", "")
    
    // Load API key from saved settings
    property string apiKey: pluginService ? pluginService.loadPluginData("steamfriends", "apikey", ""): ""
    property string steamId: pluginService ? pluginService.loadPluginData("steamfriends", "steamid", "") : ""

    // Whether the horizontal bar pill shows "X Friends Online" or just the count
    property bool showFriendsOnlineText: pluginService ? pluginService.loadPluginData("steamfriends", "showFriendsOnlineText", true) : true

    // React when settings change
    Connections {
        target: pluginService
        function onPluginDataChanged(changedPluginId, changedKey) {
            if (changedPluginId === "steamfriends" && (changedKey === "apikey" || changedKey === "steamid")) {
                apiKey = pluginService.loadPluginData("steamfriends", "apikey", "")
                steamId = pluginService.loadPluginData("steamfriends", "steamid", "")
                console.log("(SF) STEAM ID updated:", steamId) //Debug log to verify the STEAM ID is being updated
            }
            if (changedPluginId === "steamfriends" && changedKey === "showFriendsOnlineText") {
                showFriendsOnlineText = pluginService.loadPluginData("steamfriends", "showFriendsOnlineText", true)
            }
        }
    }

    // This variable determines the sorting order of the friend list, it can be toggled by the user, and it will determine how the friend list is sorted (0 = alphabetical, 1 = status)
    property int sortOrder: 1 // 0 = alphabetical, 1 = status
    
    function updateSortedList() {
        let sorted = JSON.parse(JSON.stringify(root.friendsList))
        
        if (root.sortOrder === 0) {
            // Sort alphabetically by name
            sorted.sort((a, b) => a.name.localeCompare(b.name))
        } else {
            // Sort by status (Playing first, then Online, then Away)
            const statusOrder = {"Playing": 0, "Online": 1, "Away": 2}
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

    // Process --------------------------------------------------------------------------------
    // This process runs the steam_friends.sh script to fetch the friend list and count, it expects a JSON output with 
    // the format: {"friendCount": 5, "friends": [{"name": "Friend1", "status": "Playing", "game": "Game1"}, {"name": "Friend2", "status": "Online", "game": ""}]}
    Process {
        id: friendFetcher
        command: ["sh", root.scriptPath, root.apiKey, root.steamId, "json"]
        running: root.apiKey !== "" && root.steamId !== ""

        stdout: SplitParser {
            onRead: data => {
                let output = data.trim()
                console.log("")
                console.log("-----------------------------------------------------------------------")
                console.log("(SF) Steam Friends now running...")
                console.log("(SF) STEAMID:", steamId)
                
                try {
                    let json = JSON.parse(output)
                    if (json.error) {
                        root.errorMessage = json.error
                        console.error("(SF) Script reported error:", json.error)
                    } else {
                        root.errorMessage = ""
                        root.friendCount = json.friendCount.toString()
                        root.friendsList = json.friends || []
                        root.updateSortedList()
                        root.lastUpdated = new Date()
                        console.log("(SF) Parsed count:", root.friendCount)
                        console.log("(SF) Parsed friends:", root.friendsList.length)
                    }
                } catch (e) {
                    root.errorMessage = "Failed to parse Steam response"
                    console.error("(SF) Error parsing JSON:", e)
                    console.log("(SF) Output was:", output)
                }
                console.log("")
                console.log("(SF):   ", output)
                console.log("-----------------------------------------------------------------------")
            }
        }
    }

    // Timer --------------------------------------------------------------------------------
    // This timer will refresh the friend list every 5 minutes by restarting the process
    Timer {
        interval: 300000 
        running: true
        repeat: true
        onTriggered: {
            friendFetcher.running = false
            friendFetcher.running = Qt.binding(function() { return root.apiKey !== "" && root.steamId !== "" })
        }
    }

    // V Pill -------------------------------------------------------------------------------
    // Vertical pill content - This is the content that appears in the vertical bar, it will
    verticalBarPill: Component {
        Column {
            id: verticalPillColumn
            spacing: Theme.spacingS

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

            DankIcon {
                name: "group"
                color: Theme.primary
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

    // Row -------------------------------------------------------------------------------
    // This is the popout content that appears when you click the pill, it will show a list of friends with their status and game if they are playing something
    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn
            headerText: root.friendCount + " Friends Online"
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
                        iconName: "Sort"
                        iconSize: Theme.iconSizeSmall
                        iconColor: Theme.surfaceVariantText
                        tooltipText: "Sort: " + (root.sortOrder === 0 ? "Alphabetical" : "Status")
                        onClicked: {
                            root.sortOrder = (root.sortOrder + 1) % 2
                            root.updateSortedList()
                        }
                    }
                    // Refresh button - icon-only, refreshes the friend list by restarting the process
                    DankActionButton {
                        iconName: "refresh"
                        iconSize: Theme.iconSizeSmall
                        iconColor: Theme.surfaceVariantText
                        tooltipText: "Refresh"
                        onClicked: {
                            friendFetcher.running = false
                            friendFetcher.running = Qt.binding(function() { return root.apiKey !== "" && root.steamId !== "" })
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
                color: "#F44336"
                visible: root.errorMessage.length > 0
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
                    color: Theme.surfaceContainer

                    DankListView {
                        id: friendsListView
                        anchors.fill: parent
                        spacing: Theme.spacingS
                        model: root.sortedFriendsList

                        // Group friends by game when sorted by status (game is "" for non-playing friends, so no header shows for them)
                        section.property: root.sortOrder === 1 ? "game" : ""
                        section.criteria: ViewSection.FullString
                        section.delegate: Component {
                            Item {
                                readonly property bool isTrailingBoundary: section.length === 0
                                    && root.sortedFriendsList.length > 0
                                    && (root.sortedFriendsList[0].game || "") !== ""
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
                            width: parent.width
                            height: friendRow.implicitHeight + Theme.spacingS * 2
                            color: Theme.surface
                            radius: Theme.cornerRadius
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
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.steamid) {
                                        Qt.openUrlExternally("steam://friends/message/" + modelData.steamid)
                                    }
                                }
                            }
                        }
                    }
                }

                // No friends online message
                StyledText {
                    text: "No friends online"
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.friendsList.length === 0
                }
            }
        }
    }
}
