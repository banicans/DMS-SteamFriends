#!/bin/bash

# Simplified Steam Friends Status Script
# Outputs total online friends and their status in JSON
# Usage: ./steam_friends.sh API_KEY STEAM_ID json

# Only proceed if JSON output is requested
if [[ "$3" != "json" ]]; then
    echo "Need to add 'json' as the third argument to get JSON output."
    exit 1
fi

# Set your Steam API key and Steam ID here or pass them as arguments
# Get your Steam API key from: https://steamcommunity.com/dev/apikey
# Find your Steam ID at: https://steamid.io
API_KEY="$1"
STEAM_ID="$2"

if [[ -z "$API_KEY" ]] || [[ "$API_KEY" == "YOUR_STEAM_API_KEY_HERE" ]]; then
    echo '{"error": "API_KEY not configured"}'
    exit 0
fi

if [[ -z "$STEAM_ID" ]] || [[ "$STEAM_ID" == "YOUR_STEAM_ID_HERE" ]]; then
    echo '{"error": "STEAM_ID not configured"}'
    exit 0
fi

# Get friend list
FRIEND_LIST=$(curl -sf "https://api.steampowered.com/ISteamUser/GetFriendList/v1/?key=${API_KEY}&steamid=${STEAM_ID}&relationship=friend")
if [[ $? -ne 0 ]]; then
    echo '{"error": "Failed to reach Steam API (check network or API key)"}'
    exit 0
fi

# Extract friend IDs
if command -v jq &> /dev/null; then
    FRIEND_IDS=$(echo "$FRIEND_LIST" | jq -r '.friendslist.friends[]?.steamid' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
else
    FRIEND_IDS=$(echo "$FRIEND_LIST" | grep -oP '"steamid":"?\K[0-9]+' | tr '\n' ',' | sed 's/,$//')
fi

if [[ -z "$FRIEND_IDS" ]]; then
    echo '{"error": "No friends found or API error"}'
    exit 0
fi

# Get player summaries (user's own profile + friends)
ALL_IDS="${STEAM_ID},${FRIEND_IDS}"
SUMMARIES=$(curl -sf "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=${API_KEY}&steamids=${ALL_IDS}")
if [[ $? -ne 0 ]]; then
    echo '{"error": "Failed to reach Steam API for player summaries"}'
    exit 0
fi

# Output simplified JSON
if command -v jq &> /dev/null; then
    echo "$SUMMARIES" | jq -c --arg user_id "$STEAM_ID" '{
        userAvatarUrl: ([.response.players[] | select(.steamid == $user_id)] | .[0].avatarmedium // ""),
        userPersonaName: ([.response.players[] | select(.steamid == $user_id)] | .[0].personaname // ""),
        friendCount: [.response.players[] | select(.steamid != $user_id and .personastate > 0)] | length,
        friends: [.response.players[] | select(.steamid != $user_id) | {
            name: .personaname,
            steamid: .steamid,
            status: (if .gameextrainfo then "Playing" elif .personastate == 1 then "Online" elif .personastate == 2 then "Busy" elif .personastate == 3 then "Away" elif .personastate == 4 then "Snooze" elif .personastate == 5 then "Looking to Trade" elif .personastate == 6 then "Looking to Play" elif .personastate == 0 then "Offline" else "Offline" end),
            game: (.gameextrainfo // ""),
            gameid: (.gameid // ""),
            avatarUrl: (.avatarmedium // ""),
            lastlogoff: (.lastlogoff // 0)
        }]
    }'
else
    # Fallback: basic JSON without details
    ONLINE_COUNT=$(echo "$SUMMARIES" | grep -o '"personastate":[^,]*' | grep -cE '"personastate":[123456789]' || echo 0)
    echo "{\"userAvatarUrl\":\"\",\"userPersonaName\":\"\",\"friendCount\":$ONLINE_COUNT,\"friends\":[]}"
fi

