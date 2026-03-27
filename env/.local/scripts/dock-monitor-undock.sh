#!/usr/bin/env bash
#
# dock-monitor-undock.sh
#
# Moves all i3 workspaces to the internal laptop display (eDP-1)
# and disables external monitor outputs when the Dell WD25 dock
# is disconnected.
#
# Triggered by udev rule on dock USB device removal.
#
# Monitoring:
# journalctl -t dock-hotplug -f
#

INTERNAL="eDP-1"
LOG_TAG="dock-hotplug"

log() {
    logger -t "$LOG_TAG" "$*"
}

find_display() {
    local user="$1"
    local uid
    uid=$(id -u "$user" 2>/dev/null) || return 1

    local session_display
    session_display=$(loginctl list-sessions --no-legend 2>/dev/null | \
        awk -v uid="$uid" '$2 == uid {print $1}' | head -1 | \
        xargs -I{} loginctl show-session {} -p Display --value 2>/dev/null)

    if [[ -n "$session_display" ]]; then
        echo "$session_display"
        return 0
    fi

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

    local auth="/run/user/${uid}/gdm/Xauthority"
    if [[ -f "$auth" ]]; then
        echo "$auth"
        return 0
    fi

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

log "Dock disconnected. Moving all workspaces to $INTERNAL..."

# Small delay to let the kernel finish tearing down outputs
sleep 1

# Get all workspaces and their outputs via i3-msg
workspaces=$(sudo -u "$TARGET_USER" i3-msg -t get_workspaces 2>/dev/null)

if [[ -z "$workspaces" ]]; then
    log "ERROR: could not get i3 workspace list"
    exit 1
fi

# Move each workspace that is NOT on the internal display
echo "$workspaces" | python3 -c "
import sys, json
ws_list = json.load(sys.stdin)
for ws in ws_list:
    if ws['output'] != '$INTERNAL':
        print(ws['name'])
" 2>/dev/null | while read -r ws_name; do
    log "Moving workspace '$ws_name' to $INTERNAL"
    sudo -u "$TARGET_USER" i3-msg "workspace $ws_name; move workspace to output $INTERNAL" >/dev/null 2>&1
done

# Disable external outputs that are no longer connected
sleep 1
sudo -u "$TARGET_USER" xrandr --query 2>/dev/null | \
    grep -E '^DP-.*disconnected' | awk '{print $1}' | while read -r output; do
    log "Disabling disconnected output $output"
    sudo -u "$TARGET_USER" xrandr --output "$output" --off 2>/dev/null
done

log "Undock complete. All workspaces on $INTERNAL."
