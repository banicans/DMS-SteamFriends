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

    // This variable stores the current sorting order, it can be toggled by the user, and it will determine how the friend list is sorted (0 = alphabetical, 1 = status)
    property string scriptPath: Qt.resolvedUrl("steam_friends.sh").toString().replace("file://", "")
    
    // Load API key from saved settings
    property string apiKey: pluginService ? pluginService.loadPluginData("steamfriends", "apikey", ""): ""
    property string steamId: pluginService ? pluginService.loadPluginData("steamfriends", "steamid", "") : ""

    // React when settings change
    Connections {
        target: pluginService
        function onPluginDataChanged(changedPluginId, changedKey) {
            if (changedPluginId === "myPlugin" && changedKey === "api") {
                apiKey = pluginService.loadPluginData("steamfriends", "apikey", "")
                steamID = pluginService.loadPluginData("steamfriends", "steamid", "")
                console.log("API key updated:", apiKey) //Debug log to verify the API key is being updated
                console.log("STEAM ID updated:", steamId) //Debug log to verify the STEAM ID is being updated
            }
        }
    }

    // This variable determines the sorting order of the friend list, it can be toggled by the user, and it will determine how the friend list is sorted (0 = alphabetical, 1 = status)
    property int sortOrder: 0 // 0 = alphabetical, 1 = status
    
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
                return a.name.localeCompare(b.name)
            })
        }
        
        root.sortedFriendsList = sorted
    }
    
    onFriendsListChanged: updateSortedList()

    //Process --------------------------------------------------------------------------------
    // This process runs the steam_friends.sh script to fetch the friend list and count, it expects a JSON output with 
    //the format: {"friendCount": 5, "friends": [{"name": "Friend1", "status": "Playing", "game": "Game1"}, {"name": "Friend2", "status": "Online", "game": ""}]}
    Process {
        id: friendFetcher
        command: ["sh", root.scriptPath, root.apiKey, root.steamId, "json"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                let output = data.trim()
                console.log("-----------------------------------------------------------------------")
                console.log("Raw output:", output)
                console.log("API:", root.apiKey)
                console.log("STEAMID:", steamId)
                
                try {
                    let json = JSON.parse(output)
                    root.friendCount = json.friendCount.toString()
                    root.friendsList = json.friends || []
                    root.updateSortedList()
                    console.log("Parsed count:", root.friendCount)
                    console.log("Parsed friends:", root.friendsList.length)
                } catch (e) {
                    console.error("Error parsing JSON:", e)
                    console.log("Output was:", output)
                }
                console.log("-----------------------------------------------------------------------")
            }
        } 
    }

    //Timer --------------------------------------------------------------------------------
    //This timer will refresh the friend list every 5 minutes by restarting the process
    Timer {
        interval: 300000 
        running: true
        repeat: true
        onTriggered: {
            friendFetcher.running = false
            friendFetcher.running = true
        }
    }

    //V Pill -------------------------------------------------------------------------------
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

    //H Pill -------------------------------------------------------------------------------
    // Horizontal pill content - This is the content that appears in the horizontal bar, it will show the number of friends online and an icon
    horizontalBarPill: Component {
        Row {
            id: horizontalPillRow
            spacing: Theme.spacingXS

            DankIcon {
                name: "contacts"
                color: Theme.primary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.friendCount + " Friends Online"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    //Row -------------------------------------------------------------------------------
    // This is the popout content that appears when you click the pill, it will show a list of friends with their status and game if they are playing something
    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn
            headerText: root.friendCount + " Friends Online"
            showCloseButton: true

            Row {
                id: sortRow
                width: parent.width
                spacing: Theme.spacingS
                padding: Theme.spacingM

                // Sort button - This button will toggle the sorting order between alphabetical and status
                DankButton {
                    text: root.sortOrder === 0 ? "Alphabetical" : "Status"
                    iconName: "Sort"
                    iconSize: Theme.iconSizeSmall
                    onClicked: {
                        root.sortOrder = (root.sortOrder + 1) % 2
                        root.updateSortedList()
                    }
                }
                // Refresh button - This button will refresh the friend list by restarting the process
                DankButton {
                    text: "Refresh"
                    iconName: "refresh"
                    iconSize: Theme.iconSizeSmall
                    onClicked: {
                        friendFetcher.running = false
                        friendFetcher.running = true
                    }
                }
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
                       
                        //This is each friend entry, it will show the friend's name, status, and game if they are playing something
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

                                // Status indicator (colored dot)
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: modelData.status === "Playing" ? Theme.accentColor : 
                                           modelData.status === "Online" ? "#4CAF50" :
                                           modelData.status === "Away" ? "#FFC107" :
                                           modelData.status === "Offline" ? "#F44336" : "#9C27B0"
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
                                    //Status or game info
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
                        }
                        ScrollBar.vertical: DankScrollbar {
                        id: scrollbar
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
