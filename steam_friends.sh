#!/bin/bash

# Simplified Steam Friends Status Script
# Outputs total online friends and their status in JSON
# Usage: STEAM_API_KEY=... STEAM_ID=... ./steam_friends.sh
#    or: ./steam_friends.sh API_KEY STEAM_ID

# Credentials come from environment variables (used by the widget, keeps them out of the process list)
# or from arguments for running it by hand
# Get your Steam API key from: https://steamcommunity.com/dev/apikey
# Find your Steam ID at: https://steamid.io
API_KEY="${STEAM_API_KEY:-$1}"
STEAM_ID="${STEAM_ID:-$2}"

if [[ -z "$API_KEY" ]] || [[ "$API_KEY" == "YOUR_STEAM_API_KEY_HERE" ]]; then
    echo '{"error": "API_KEY not configured"}'
    exit 0
fi

if [[ -z "$STEAM_ID" ]] || [[ "$STEAM_ID" == "YOUR_STEAM_ID_HERE" ]]; then
    echo '{"error": "STEAM_ID not configured"}'
    exit 0
fi

if ! command -v jq &> /dev/null; then
    echo '{"error": "jq is required but not installed"}'
    exit 0
fi

# Fetches a URL, passing it to curl through stdin so the API key doesn't appear in curl's arguments
fetch() {
    curl -sf -K - <<< "url = \"$1\""
}

# Get friend list
FRIEND_LIST=$(fetch "https://api.steampowered.com/ISteamUser/GetFriendList/v1/?key=${API_KEY}&steamid=${STEAM_ID}&relationship=friend")
if [[ $? -ne 0 ]]; then
    echo '{"error": "Failed to reach Steam API (check network or API key)"}'
    exit 0
fi

# Extract friend IDs
mapfile -t FRIEND_IDS < <(echo "$FRIEND_LIST" | jq -r '.friendslist.friends[]?.steamid' 2>/dev/null)

if [[ ${#FRIEND_IDS[@]} -eq 0 ]]; then
    # A valid response with no friends just means nobody to show, anything else is an API error
    if echo "$FRIEND_LIST" | jq -e '.friendslist' &> /dev/null; then
        echo '{"friendCount": 0, "friends": []}'
    else
        echo '{"error": "Unexpected response from Steam API"}'
    fi
    exit 0
fi

# Get player summaries - the API accepts at most 100 Steam IDs per request, so fetch in batches
SUMMARIES=""
for ((i = 0; i < ${#FRIEND_IDS[@]}; i += 100)); do
    BATCH=$(IFS=,; echo "${FRIEND_IDS[*]:i:100}")
    RESPONSE=$(fetch "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=${API_KEY}&steamids=${BATCH}")
    if [[ $? -ne 0 ]]; then
        echo '{"error": "Failed to reach Steam API for player summaries"}'
        exit 0
    fi
    SUMMARIES+="$RESPONSE"
done

# Output simplified JSON
echo "$SUMMARIES" | jq -sc '[.[].response.players[] | select(.personastate > 0)] | {
    friendCount: length,
    friends: [.[] | {
        name: .personaname,
        steamid: .steamid,
        status: (if .gameextrainfo then "Playing" elif .personastate == 1 then "Online" elif .personastate == 2 then "Busy" elif .personastate == 3 then "Away" elif .personastate == 4 then "Snooze" elif .personastate == 5 then "Looking to Trade" elif .personastate == 6 then "Looking to Play" else "Unknown" end),
        game: (.gameextrainfo // ""),
        gameid: (.gameid // ""),
        avatarUrl: (.avatarmedium // "")
    }]
}' 2>/dev/null || echo '{"error": "Unexpected response from Steam API"}'
