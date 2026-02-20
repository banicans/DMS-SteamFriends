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

# Exit on error
set -e

if [[ -z "$API_KEY" ]] || [[ "$API_KEY" == "YOUR_STEAM_API_KEY_HERE" ]]; then
    echo "{\"error\": \"API_KEY not configured\"}" >&2
    exit 1
fi

if [[ -z "$STEAM_ID" ]] || [[ "$STEAM_ID" == "YOUR_STEAM_ID_HERE" ]]; then
    echo "{\"error\": \"STEAM_ID not configured\"}" >&2
    exit 1
fi

# Get friend list
FRIEND_LIST=$(curl -s "https://api.steampowered.com/ISteamUser/GetFriendList/v1/?key=${API_KEY}&steamid=${STEAM_ID}&relationship=friend")

# Extract friend IDs
if command -v jq &> /dev/null; then
    FRIEND_IDS=$(echo "$FRIEND_LIST" | jq -r '.friendslist.friends[].steamid' | tr '\n' ',' | sed 's/,$//')
else
    FRIEND_IDS=$(echo "$FRIEND_LIST" | grep -oP '"steamid":"?\K[0-9]+' | tr '\n' ',' | sed 's/,$//')
fi

if [[ -z "$FRIEND_IDS" ]]; then
    echo "{\"error\": \"No friends found or API error\"}" >&2
    exit 1
fi

# Get player summaries
SUMMARIES=$(curl -s "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=${API_KEY}&steamids=${FRIEND_IDS}")

# Output simplified JSON
if command -v jq &> /dev/null; then
    echo "$SUMMARIES" | jq -c '{
        friendCount: [.response.players[] | select(.personastate > 0)] | length,
        friends: [.response.players[] | select(.personastate > 0) | {
            name: .personaname,
            status: (if .personastate == 1 then "Online" elif .personastate == 2 then "Busy" elif .personastate == 3 then "Away" elif .personastate == 4 then "Snooze" elif .personastate == 5 then "Looking to Trade" elif .personastate == 6 then "Looking to Play" else "Unknown" end)
        }]
    }'
else
    # Fallback: basic JSON without details
    ONLINE_COUNT=$(echo "$SUMMARIES" | grep -o '"personastate":[^,]*' | grep -cE '"personastate":[123456789]' || echo 0)
    echo "{\"friendCount\":$ONLINE_COUNT,\"friends\":[]}"
fi
