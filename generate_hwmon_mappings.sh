#!/usr/bin/env zsh

# Script to create a CSV table of hwmon devices
# Maps hwmon directories to their device models and names for fancontrol configuration

# Default output path
output_path="/etc/fancontrol_mappings"
check_mode=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-path)
            output_path="$2"
            shift 2
            ;;
        --check)
            check_mode=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--output-path PATH] [--check]" >&2
            exit 1
            ;;
    esac
done

# Function to generate the CSV content
# Iterates through /sys/class/hwmon/hwmon* and extracts device model and name
generate_csv() {
    # CSV header
    echo "hwmon,device_model,name"
    
    # Navigate to hwmon directory
    if ! cd /sys/class/hwmon 2>/dev/null; then
        echo "Error: Cannot access /sys/class/hwmon" >&2
        return 1
    fi
    
    # Iterate over hwmon* directories, sorted numerically
    # <-> matches one or more digits, (n) sorts numerically
    for hwmon_dir in hwmon<->(n); do
        if [[ -d "$hwmon_dir" ]]; then
            hwmon_name="$hwmon_dir"
            
            # Get device model (may not exist for all devices)
            device_model=""
            if [[ -f "$hwmon_dir/device/model" ]]; then
                device_model=$(cat "$hwmon_dir/device/model" 2>/dev/null | tr -d '\n')
            fi
            
            # Get name from the hwmon device
            name=""
            if [[ -f "$hwmon_dir/name" ]]; then
                name=$(cat "$hwmon_dir/name" 2>/dev/null | tr -d '\n')
            fi
            
            # Output CSV row
            echo "$hwmon_name,$device_model,$name"
        fi
    done
}

# Generate new CSV content
new_content=$(generate_csv)

# Check if generation failed
if [[ $? -ne 0 ]]; then
    exit 1
fi

if $check_mode; then
    # Check mode: compare with existing file and show diff if different
    if [[ -f "$output_path" ]]; then
        old_content=$(cat "$output_path")
        
        if [[ "$new_content" != "$old_content" ]]; then
            echo "Content has changed. Diff:" >&2
            # Create temporary files for diff
            temp_old=$(mktemp)
            temp_new=$(mktemp)
            echo "$old_content" > "$temp_old"
            echo "$new_content" > "$temp_new"
            diff -u "$temp_old" "$temp_new"
            rm -f "$temp_old" "$temp_new"
            exit 1
        else
            # Content is the same, exit successfully without touching the file
            exit 0
        fi
    else
        echo "Error: Output file does not exist: $output_path" >&2
        exit 1
    fi
else
    # Normal mode: save to file
    echo "$new_content" > "$output_path"
    echo "CSV table saved to $output_path"
fi
