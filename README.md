# Fancontrol Parser

A utility script to automatically update hwmon device numbers in the fancontrol configuration file when they change after system reboot.

## Background

On Linux systems using lm-sensors and fancontrol, the hwmon device numbers (e.g., hwmon0, hwmon1) can change between reboots. This causes the fancontrol service to fail since it relies on these device numbers in its configuration. This script automatically detects and updates these numbers, ensuring your fan control settings persist across reboots.

## Features

- Automatically detects current hwmon numbers for coretemp and f71869a devices
- Updates the fancontrol configuration file with new device numbers
- Restarts the fancontrol service automatically
- Dry run mode to preview changes
- Quiet mode for silent operation
- Safety checks to prevent unnecessary updates

## Prerequisites

- ZSH shell
- lm-sensors and fancontrol packages installed
- Root privileges (for modifying /etc/fancontrol)

## Installation

1. Clone this repository:
```bash
git clone https://github.com/yourusername/fancontrol-parser.git
```

2. Make the script executable:
```bash
chmod +x fancontrol_parser.sh
```

## Usage

```bash
./fancontrol_parser.sh [-q|--quiet] [-d|--dry]
```

Options:
- `-q, --quiet`: Suppress output messages
- `-d, --dry`: Dry run mode - show what would change without making changes

## Example

```bash
sudo ./fancontrol_parser.sh
```

This will:
1. Check if fancontrol service is already running
2. Find current hwmon numbers for coretemp and f71869a devices
3. Update the configuration if numbers have changed
4. Restart the fancontrol service

## Automatic Execution

You can add this script to your system's startup sequence to ensure fan control works correctly after every reboot. One way to do this is by creating a systemd service that runs before the fancontrol service.

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
