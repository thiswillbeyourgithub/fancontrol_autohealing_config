#!/bin/zsh

# Updates hwmon device numbers in fancontrol configuration when they change after reboot

# Usage: fancontrol_parser.sh [-q|--quiet] [-d|--dry] --fandevice=<device>
#   -q, --quiet    Suppress output messages
#   -d, --dry      Dry run mode - show what would change without making changes
#   --fandevice    Specify the fan device (e.g., --fandevice=nct6775)

zparseopts -D -E \
    q=quiet -quiet=quiet \
    d=dry -dry=dry \
    -fandevice:=fandevice \

# Extract the value of --fandevice
if [[ -n "$fandevice" ]]; then
    fandevice="${fandevice[2]}"  # Extract the value from the array
fi

log() {
    if [[ ! "$quiet" ]]
    then
        echo "$@"
    fi
}

if [[ -z $fandevice ]]
then
    echo "You have to specify a --fandevice like --fandevice nct6775 (use a space, not an equal sign)"
    exit 1
fi

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

# Read the fancontrol file and extract current assignments from DEVNAME line
while IFS= read -r line; do
    if [[ "$line" == "DEVNAME="* ]]; then
        # Extract the DEVNAME line content
        devname_content=${line#DEVNAME=}
        
        # Parse each hwmon assignment
        for assignment in $devname_content; do
            # Split the hwmon=device pair
            hwmon=${assignment%=*}
            device=${assignment#*=}
            
            # Store the hwmon number for each device
            if [[ "$device" == "coretemp" ]]; then
                old_coretemp=$hwmon
            elif [[ "$device" == "$fandevice" ]]; then
                old_fandevice=$hwmon
            fi
        done
    fi
done < "$FANCONTROL_FILE"

# Find current hwmon numbers
new_coretemp=$(find_current_hwmon "coretemp")
new_fandevice=$(find_current_hwmon "$fandevice")

log "coretemp: $old_coretemp -> $new_coretemp"
log "$fandevice: $old_fandevice -> $new_fandevice"

if [[ "$new_coretemp" == "Error*" || "$new_fandevice" == "Error*" ]]; then
    log "Failed to find the hwmon of some devices!"
    exit 1
fi

# Check if the new hwmon numbers are different from the old ones
if [[ "$new_coretemp" == "$old_coretemp" && "$new_fandevice" == "$old_fandevice" ]]; then
    log "No changes needed - hwmon numbers are the same"
    exit 0
fi

if [[ $dry ]]
then
    log "Exit without modification because in dry mode"
    exit 0
fi

# Only proceed if we found both devices
if [[ -n "$new_coretemp" && -n "$new_fandevice" ]]; then
    # Create temporary file
    temp_file=$(mktemp)
    
    # Use placeholder to avoid conflicts during substitution
    placeholder="TEMP_HWMON_PLACEHOLDER"
    
    # First replace coretemp with placeholder
    sed "s/$old_coretemp/$placeholder/g" "$FANCONTROL_FILE" > "$temp_file"
    
    # Then replace fandevice
    sed "s/$old_fandevice/$new_fandevice/g" "$temp_file" > "${temp_file}.2"
    
    # Finally replace placeholder with new coretemp
    sed "s/$placeholder/$new_coretemp/g" "${temp_file}.2" > "$FANCONTROL_FILE"
    
    # Clean up additional temp file
    rm "${temp_file}.2"
    
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
