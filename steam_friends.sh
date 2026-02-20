#!/bin/bash

# Steam Friends Status Script
# Displays online friends, their status, and current game
# Usage: ./steam_friends.sh [json]
# Add 'json' argument for JSON output suitable for QML parsing

# Configure these variables:
API_KEY="$1"
STEAM_ID="$2"
echo "(Script) API_KEY: $API_KEY"
echo "(Script) STEAM_ID: $STEAM_ID"  
# Get your Steam API key from: https://steamcommunity.com/dev/apikey
# Find your Steam ID at: https://steamid.io


# Exit on error
set -e 

if [[ -z "$API_KEY" ]] || [[ "$API_KEY" == "YOUR_STEAM_API_KEY_HERE" ]]; then
    echo "(Script) Error: API_KEY not configured. Edit the script and set your Steam API key."
    exit 1
fi

if [[ -z "$STEAM_ID" ]] || [[ "$STEAM_ID" == "YOUR_STEAM_ID_HERE" ]]; then
    echo "(Script) Error: STEAM_ID not configured. Edit the script and set your Steam ID."
    exit 1
fi


# Check if JSON output is requested
JSON_OUTPUT=false
if [[ "$1" == "json" ]]; then
    JSON_OUTPUT=true
fi

# Color codes for output (not used in JSON mode)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [[ "$JSON_OUTPUT" != true ]]; then
    echo -e "${BLUE}Fetching friend data...${NC}"
fi

# Get friend list
FRIEND_LIST=$(curl -s "https://api.steampowered.com/ISteamUser/GetFriendList/v1/?key=${API_KEY}&steamid=${STEAM_ID}&relationship=friend")

# Extract friend IDs using jq or fallback to grep
if command -v jq &> /dev/null; then
    FRIEND_IDS=$(echo "$FRIEND_LIST" | jq -r '.friendslist.friends[].steamid' | tr '\n' ',' | sed 's/,$//')
else
    FRIEND_IDS=$(echo "$FRIEND_LIST" | grep -oP '"steamid":"?\K[0-9]+' | tr '\n' ',' | sed 's/,$//')
fi

if [[ -z "$FRIEND_IDS" ]]; then
    echo "No friends found or API error. Check your API key and Steam ID."
    echo "Response: $FRIEND_LIST"
    exit 1
fi

# Get player summaries for all friends
SUMMARIES=$(curl -s "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=${API_KEY}&steamids=${FRIEND_IDS}")

# Parse and display friend data
if command -v jq &> /dev/null; then
    # Use jq for JSON parsing if available
    ONLINE_COUNT=$(echo "$SUMMARIES" | jq '[.response.players[] | select(.personastate > 0)] | length')
else
    # Fallback to grep
    ONLINE_COUNT=$(echo "$SUMMARIES" | grep -o '"personastate":[^,]*' | grep -cE '"personastate":[123456789]' || echo 0)
fi

# Output in JSON format for QML
if [[ "$JSON_OUTPUT" == true ]]; then
    if command -v jq &> /dev/null; then
        # Generate JSON output
        echo "$SUMMARIES" | jq -c --arg count "$ONLINE_COUNT" '{
            friendCount: ($count | tonumber),
            friends: [.response.players[] | select(.personastate > 0) | {
                name: .personaname,
                status: if .personastate == 1 then "Online" elif .personastate == 3 then "Away" elif .personastate == 2 then "Busy" elif .personastate == 4 then "Snooze" elif .personastate == 5 then "Looking to trade" elif .personastate == 6 then "Looking to play" else "Unknown" end,
                game: (.gameextrainfo // "")
            }]
        }'
    else
        # Fallback: simple JSON without jq
        echo "{\"friendCount\": $ONLINE_COUNT, \"friends\": []}"
    fi
    exit 0
fi

# Regular text output
echo ""
echo -e "${BLUE}=== Steam Friends Status ===${NC}"
echo -e "Total friends online: ${GREEN}${ONLINE_COUNT}${NC}"
echo ""
echo -e "${BLUE}Friends:${NC}"
echo "---"

# Parse and display friends
if command -v jq &> /dev/null; then
    echo "$SUMMARIES" | jq -r '.response.players[] | select(.personastate > 0) |
        @text "\(.personaname)|\(.personastate)|\(.gameextrainfo // "")"' | while IFS='|' read -r NAME STATE GAME; do
        case "$STATE" in
            0) STATUS="Offline" ; COLOR="$RED" ;;
            1) STATUS="Online" ; COLOR="$GREEN" ;;
            2) STATUS="Busy" ; COLOR="$RED" ;;
            3) STATUS="Away" ; COLOR="$YELLOW" ;;
            4) STATUS="Snooze" ; COLOR="$YELLOW" ;;
            5) STATUS="Looking to trade" ; COLOR="$BLUE" ;;
            6) STATUS="Looking to play" ; COLOR="$BLUE" ;;
            *) STATUS="Unknown" ; COLOR="$NC" ;;
        esac
        
        printf "  ${COLOR}●${NC} %s" "$NAME"
        
        if [[ -n "$GAME" ]]; then
            printf " - Playing: %s\n" "$GAME"
        else
            printf " - %s\n" "$STATUS"
        fi
    done
else
    # Fallback grep-based parsing
    echo "$SUMMARIES" | grep -oP '"personaname":"\K[^"]+|"personastate":\K[0-9]+|"gameextrainfo":"\K[^"]+' | while read -r NAME; do
        read -r STATE
        read -r GAME 2>/dev/null || GAME=""
        
        case "$STATE" in
            0) STATUS="Offline" ; COLOR="$RED" ;;
            1) STATUS="Online" ; COLOR="$GREEN" ;;
            2) STATUS="Busy" ; COLOR="$RED" ;;
            3) STATUS="Away" ; COLOR="$YELLOW" ;;
            4) STATUS="Snooze" ; COLOR="$YELLOW" ;;
            5) STATUS="Looking to trade" ; COLOR="$BLUE" ;;
            6) STATUS="Looking to play" ; COLOR="$BLUE" ;;
            *) STATUS="Unknown" ; COLOR="$NC" ;;
        esac
        
        if [[ "$STATE" -gt 0 ]]; then
            echo -ne "  ${COLOR}●${NC} "
            echo -n "$NAME"
            
            if [[ -n "$GAME" ]]; then
                echo " - Playing: $GAME"
            else
                echo " - $STATUS"
            fi
        fi
    done
fi

echo "---"
echo ""
