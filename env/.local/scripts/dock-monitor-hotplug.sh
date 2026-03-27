#!/usr/bin/env bash
#
# dock-monitor-hotplug.sh
#
# Workaround for Dell WD25 dock + Intel Arrow Lake DP alt mode
# negotiation failure on hot-plug. The monitors are detected by
# xrandr but remain blank until outputs are cycled off/on.
#
# Triggered by udev rule on dock USB device connect.
#
# Monitoring:
# journalctl -t dock-hotplug -f
#
# Manual Workaround (without this script):
# xrandr --output DP-2-2-2 --off --output DP-2-3-3 --off
# sleep 2
# xrandr --output DP-2-2-2 --mode 1920x1080 --right-of eDP-1 \
#     --output DP-2-3-3 --mode 1920x1080 --right-of DP-2-2-2
#

DOCK_SETTLE_DELAY=5
MONITOR_LEFT="DP-2-2-2"
MONITOR_RIGHT="DP-2-3-3"
INTERNAL="eDP-1"
RESOLUTION="1920x1080"

LOG_TAG="dock-hotplug"

log() {
    logger -t "$LOG_TAG" "$*"
}

# Find the active X session for our user
find_display() {
    local user="$1"
    local uid
    uid=$(id -u "$user" 2>/dev/null) || return 1

    # Try loginctl first
    local session_display
    session_display=$(loginctl list-sessions --no-legend 2>/dev/null | \
        awk -v uid="$uid" '$2 == uid {print $1}' | head -1 | \
        xargs -I{} loginctl show-session {} -p Display --value 2>/dev/null)

    if [[ -n "$session_display" ]]; then
        echo "$session_display"
        return 0
    fi

    # Fallback: check /tmp/.X11-unix
    if [[ -S /tmp/.X11-unix/X0 ]]; then
        echo ":0"
        return 0
    fi

    return 1
}

find_xauthority() {
    local user="$1"
    local uid
    uid=$(id -u "$user" 2>/dev/null) || return 1

    # GDM session path
    local auth="/run/user/${uid}/gdm/Xauthority"
    if [[ -f "$auth" ]]; then
        echo "$auth"
        return 0
    fi

    # Fallback
    auth="/home/${user}/.Xauthority"
    if [[ -f "$auth" ]]; then
        echo "$auth"
        return 0
    fi

    return 1
}

TARGET_USER="dgilli"

DISPLAY=$(find_display "$TARGET_USER") || {
    log "ERROR: could not determine DISPLAY for $TARGET_USER"
    exit 1
}
export DISPLAY

XAUTHORITY=$(find_xauthority "$TARGET_USER") || {
    log "ERROR: could not determine XAUTHORITY for $TARGET_USER"
    exit 1
}
export XAUTHORITY

log "Dock connected. Waiting ${DOCK_SETTLE_DELAY}s for link to settle..."
sleep "$DOCK_SETTLE_DELAY"

# Check if the monitors are already showing as connected and active
connected_count=$(sudo -u "$TARGET_USER" xrandr --query 2>/dev/null | \
    grep -cE "^($MONITOR_LEFT|$MONITOR_RIGHT) connected [0-9]")

if [[ "$connected_count" -ge 2 ]]; then
    log "Both monitors already active, skipping cycle"
    exit 0
fi

# Check if the MST outputs exist at all in xrandr
has_outputs=$(sudo -u "$TARGET_USER" xrandr --query 2>/dev/null | \
    grep -cE "^($MONITOR_LEFT|$MONITOR_RIGHT)")

if [[ "$has_outputs" -lt 2 ]]; then
    log "MST outputs not yet enumerated ($has_outputs/2), waiting 5 more seconds..."
    sleep 5
    has_outputs=$(sudo -u "$TARGET_USER" xrandr --query 2>/dev/null | \
        grep -cE "^($MONITOR_LEFT|$MONITOR_RIGHT)")
    if [[ "$has_outputs" -lt 2 ]]; then
        log "ERROR: MST outputs still not available ($has_outputs/2), giving up"
        exit 1
    fi
fi

log "Cycling monitor outputs off..."
sudo -u "$TARGET_USER" xrandr \
    --output "$MONITOR_LEFT" --off \
    --output "$MONITOR_RIGHT" --off 2>&1 | while read -r line; do log "$line"; done

sleep 2

log "Bringing monitors back on..."
sudo -u "$TARGET_USER" xrandr \
    --output "$MONITOR_LEFT" --mode "$RESOLUTION" --right-of "$INTERNAL" \
    --output "$MONITOR_RIGHT" --mode "$RESOLUTION" --right-of "$MONITOR_LEFT" \
    2>&1 | while read -r line; do log "$line"; done

sleep 1

# Verify
active_count=$(sudo -u "$TARGET_USER" xrandr --query 2>/dev/null | \
    grep -cE "^($MONITOR_LEFT|$MONITOR_RIGHT) connected [0-9]")

if [[ "$active_count" -ge 2 ]]; then
    log "SUCCESS: $active_count monitors active"
else
    log "WARNING: only $active_count/2 monitors active after cycle"
fi
