#!/bin/zsh

# Updates hwmon device numbers in fancontrol configuration when they change after reboot

# Usage: fancontrol_parser.sh [-q|--quiet] [-d|--dry]
#   -q, --quiet    Suppress output messages
#   -d, --dry      Dry run mode - show what would change without making changes

zparseopts -D -E \
q=quiet -quiet=quiet \
d=dry -dry=dry \

log() {
    if [[ ! "$quiet" ]]
    then
        echo "$@"
    fi
}

if [[ $dry ]]
then
    unset quiet
    echo "Dry mode"
fi

# Check if fancontrol service is already running
if systemctl is-active --quiet fancontrol.service; then
    log "Fancontrol service is already running. No need to update."
    exit 0
fi

# Configuration file path
FANCONTROL_FILE="/etc/fancontrol"

# Function to find current hwmon number for a device
find_current_hwmon() {
    local device_name=$1
    
    # Check if argument is empty
    if [[ -z "$device_name" ]]; then
        log "Error: Empty device name provided to find_current_hwmon"
        exit 1
    fi
    
    local current_hwmon=""
    
    # Iterate through hwmon directories
    for hwmon_dir in /sys/class/hwmon/hwmon*; do
        # Check name file in main directory
        if [[ -f "$hwmon_dir/name" ]]; then
            local name=$(cat "$hwmon_dir/name")
            if [[ "$name" == "$device_name" ]]; then
                current_hwmon=$(basename "$hwmon_dir")
                break
            fi
        # Check name file in device subdirectory
        elif [[ -f "$hwmon_dir/device/name" ]]; then
            local name=$(cat "$hwmon_dir/device/name")
            if [[ "$name" == "$device_name" ]]; then
                current_hwmon=$(basename "$hwmon_dir")
                break
            fi
        fi
    done
    
    # Check if we found a hwmon
    if [[ -z "$current_hwmon" ]]; then
        log "Error: Could not find hwmon for device $device_name"
        exit 1
    fi
    
    log "$current_hwmon"
}

# Read the fancontrol file and extract current assignments
while IFS= read -r line; do
    if [[ "$line" == "#### coretemp="* ]]; then
        old_coretemp=${line#*=}
    elif [[ "$line" == "#### f71869a="* ]]; then
        old_f71869a=${line#*=}
    fi
done < "$FANCONTROL_FILE"

# Find current hwmon numbers
new_coretemp=$(find_current_hwmon "coretemp")
new_f71869a=$(find_current_hwmon "f71869a")

# Check if the new hwmon numbers are different from the old ones
if [[ "$new_coretemp" == "$old_coretemp" && "$new_f71869a" == "$old_f71869a" ]]; then
    log "No changes needed - hwmon numbers are the same"
    exit 0
fi

log "coretemp: $old_coretemp -> $new_coretemp"
log "f71869a: $old_f71869a -> $new_f71869a"

if [[ $dry ]]
then
    log "Exit without modification because in dry mode"
    exit 0
fi

# Only proceed if we found both devices
if [[ -n "$new_coretemp" && -n "$new_f71869a" ]]; then
    # Create temporary file
    temp_file=$(mktemp)
    
    # First replace coretemp
    sed "s/$old_coretemp/$new_coretemp/g" "$FANCONTROL_FILE" > "$temp_file"
    
    # Then replace f71869a
    sed "s/$old_f71869a/$new_f71869a/g" "$temp_file" > "$FANCONTROL_FILE"
    
    # Clean up
    rm "$temp_file"
    
    log "Updated hwmon assignments:"
    
    # Restart fancontrol service
    if ! systemctl restart fancontrol.service; then
        log "Error: Failed to restart fancontrol service"
        exit 1
    fi
    log "Fancontrol service restarted successfully"
else
    log "Error: Could not find all required hwmon devices"
    exit 1
fi
