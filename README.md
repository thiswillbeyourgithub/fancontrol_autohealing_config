# Fancontrol Parser

A Python utility to automatically update hwmon device numbers in the fancontrol configuration file when they change after system reboot.

## Background

On Linux systems using lm-sensors and fancontrol, the hwmon device numbers (e.g., hwmon0, hwmon1) can change between reboots. This causes the fancontrol service to fail since it relies on these device numbers in its configuration. This script automatically detects and updates these numbers, ensuring your fan control settings persist across reboots.

## Features

- Automatically detects current hwmon numbers for coretemp and fan devices
- Updates the fancontrol configuration file with new device numbers
- Restarts the fancontrol service automatically
- Dry run mode to preview changes
- Quiet mode for silent operation
- Safety checks to prevent unnecessary updates

## Prerequisites

- Python 3
- lm-sensors and fancontrol packages installed
- Root privileges (for modifying /etc/fancontrol)

## Installation

1. Clone this repository:
```bash
git clone https://github.com/thiswillbeyourgithub/fancontrol-parser.git
```

## Usage

```bash
sudo python3 fancontrol_parser.py [--quiet] [--apply]
```

Options:
- `--quiet, -q`: Suppress output messages
- `--apply, -a`: Apply changes (without this flag, runs in dry-run mode)

## Example

```bash
sudo python3 fancontrol_parser.py --apply
```

This will:
1. Check if fancontrol service is already running
2. Find current hwmon numbers for coretemp and fan devices
3. Update the configuration if numbers have changed
4. Restart the fancontrol service

## Automatic Execution

You can add this script to your system's startup sequence to ensure fan control works correctly after every reboot. One way to do this is by creating a systemd service that runs before the fancontrol service:

```bash
# Create a systemd service file
sudo nano /etc/systemd/system/fancontrol-parser.service
```

Add the following content:

```
[Unit]
Description=Update hwmon device numbers in fancontrol config
Before=fancontrol.service
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /path/to/fancontrol_parser.py --apply

[Install]
WantedBy=multi-user.target
```

Then enable the service:

```bash
sudo systemctl enable fancontrol-parser.service
```

## License

GPLv3

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
