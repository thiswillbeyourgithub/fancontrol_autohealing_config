import re
import sys
import os
import subprocess
from tempfile import mktemp

def log(message, quiet=False):
    if not quiet:
        print(message)

def find_current_hwmon(device_name):
    """Find the current hwmon number for a given device."""
    if not device_name:
        log("Error: Empty device name provided to find_current_hwmon")
        sys.exit(1)

    for hwmon_dir in os.listdir('/sys/class/hwmon/'):
        hwmon_path = os.path.join('/sys/class/hwmon/', hwmon_dir)
        name_path = os.path.join(hwmon_path, 'name')
        device_name_path = os.path.join(hwmon_path, 'device', 'name')

        if os.path.exists(name_path):
            with open(name_path, 'r') as f:
                name = f.read().strip()
                if name == device_name:
                    return hwmon_dir

        if os.path.exists(device_name_path):
            with open(device_name_path, 'r') as f:
                name = f.read().strip()
                if name == device_name:
                    return hwmon_dir

    log(f"Error: Could not find hwmon for device {device_name}")
    sys.exit(1)

def main():
    # Parse command line arguments
    args = sys.argv[1:]
    quiet = '-q' in args or '--quiet' in args
    apply = '-a' in args or '--apply' in args

    if not apply:
        log("Dry mode (use --apply to make changes)")

    # Check if fancontrol service is already running
    if subprocess.run(["systemctl", "is-active", "--quiet", "fancontrol.service"]).returncode == 0:
        log("Fancontrol service is already running. No need to update.")
        sys.exit(0)

    # Configuration file path
    FANCONTROL_FILE = "/etc/fancontrol"

    # Read the fancontrol file and extract current assignments from DEVNAME line
    old_coretemp = None
    old_fandevice = None
    fandevice = None

    with open(FANCONTROL_FILE, 'r') as f:
        for line in f:
            if line.startswith("DEVNAME="):
                devname_content = line.strip()[8:]  # Remove "DEVNAME="
                for assignment in devname_content.split():
                    hwmon, device = assignment.split('=')
                    if device == "coretemp":
                        old_coretemp = hwmon
                    elif device != "coretemp":
                        old_fandevice = hwmon
                        fandevice = device
    
    if not fandevice:
        log("Error: Could not find fan device in fancontrol file")
        sys.exit(1)

    # Find current hwmon numbers
    new_coretemp = find_current_hwmon("coretemp")
    new_fandevice = find_current_hwmon(fandevice)

    log(f"coretemp: {old_coretemp} -> {new_coretemp}")
    log(f"{fandevice}: {old_fandevice} -> {new_fandevice}")

    if new_coretemp.startswith("Error") or new_fandevice.startswith("Error"):
        log("Failed to find the hwmon of some devices!")
        sys.exit(1)

    # Check if the new hwmon numbers are different from the old ones
    if new_coretemp == old_coretemp and new_fandevice == old_fandevice:
        log("No changes needed - hwmon numbers are the same")
        sys.exit(0)

    if not apply:
        log("Exit without modification because --apply was not specified")
        sys.exit(0)

    # Only proceed if we found both devices
    if new_coretemp and new_fandevice:
        # Create temporary file
        temp_file = mktemp()
        placeholder = "TEMP_HWMON_PLACEHOLDER"

        # First replace coretemp with placeholder
        with open(FANCONTROL_FILE, 'r') as f, open(temp_file, 'w') as temp_f:
            for line in f:
                temp_f.write(line.replace(old_coretemp, placeholder))

        # Then replace fandevice
        with open(temp_file, 'r') as temp_f, open(f"{temp_file}.2", 'w') as temp_f2:
            for line in temp_f:
                temp_f2.write(line.replace(old_fandevice, new_fandevice))

        # Finally replace placeholder with new coretemp
        with open(f"{temp_file}.2", 'r') as temp_f2, open(FANCONTROL_FILE, 'w') as f:
            for line in temp_f2:
                f.write(line.replace(placeholder, new_coretemp))

        # Clean up additional temp file
        os.remove(f"{temp_file}.2")
        os.remove(temp_file)

        log("Updated hwmon assignments:")

        # Restart fancontrol service
        if subprocess.run(["systemctl", "restart", "fancontrol.service"]).returncode != 0:
            log("Error: Failed to restart fancontrol service")
            sys.exit(1)
        log("Fancontrol service restarted successfully")
    else:
        log("Error: Could not find all required hwmon devices")
        sys.exit(1)

if __name__ == "__main__":
    main()
