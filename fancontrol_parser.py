import re
import sys
import os
import subprocess

FANCONTROL_FILE = "/etc/fancontrol"


def log(message, quiet=False):
    if not quiet:
        print(message)


def live_hwmon_state():
    """Scan /sys/class/hwmon and return a list of dicts with hwmon name,
    driver name, and devpath (the form stored by fancontrol in DEVPATH=)."""
    entries = []
    for hwmon in sorted(os.listdir('/sys/class/hwmon/')):
        base = f'/sys/class/hwmon/{hwmon}'

        name = ''
        try:
            with open(f'{base}/name') as f:
                name = f.read().strip()
        except OSError:
            pass

        devpath = ''
        try:
            target = os.readlink(base)
            full = os.path.normpath(os.path.join('/sys/class/hwmon', target))
            if full.startswith('/sys/'):
                full = full[len('/sys/'):]
            suffix = f'/hwmon/{hwmon}'
            if full.endswith(suffix):
                full = full[:-len(suffix)]
            devpath = full
        except OSError:
            pass

        entries.append({'hwmon': hwmon, 'name': name, 'devpath': devpath})
    return entries


def parse_fancontrol(path):
    """Return {hwmonX: {'name': driver, 'devpath': devpath}} from DEVPATH= and DEVNAME= lines."""
    entries = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith('DEVPATH='):
                for assignment in line[len('DEVPATH='):].split():
                    hwmon, dp = assignment.split('=', 1)
                    entries.setdefault(hwmon, {})['devpath'] = dp
            elif line.startswith('DEVNAME='):
                for assignment in line[len('DEVNAME='):].split():
                    hwmon, dn = assignment.split('=', 1)
                    entries.setdefault(hwmon, {})['name'] = dn
    return entries


def resolve_mapping(old_entries, live):
    """Compute {old_hwmon: new_hwmon}. Match by DEVPATH first (stable across reboots),
    fall back to driver name when it identifies a unique live hwmon."""
    by_devpath = {h['devpath']: h['hwmon'] for h in live if h['devpath']}
    by_name = {}
    for h in live:
        by_name.setdefault(h['name'], []).append(h['hwmon'])

    mapping = {}
    for old_hwmon, info in old_entries.items():
        dp = info.get('devpath', '')
        if dp and dp in by_devpath:
            mapping[old_hwmon] = by_devpath[dp]
            continue
        candidates = by_name.get(info.get('name', ''), [])
        if len(candidates) == 1:
            mapping[old_hwmon] = candidates[0]
            continue
        return None, (f"Could not resolve {old_hwmon} "
                      f"(devpath={dp!r}, name={info.get('name', '')!r}, "
                      f"name candidates={candidates})")
    return mapping, None


def rewrite_content(content, renumber):
    """Substitute old hwmonX -> new hwmonX in fancontrol content. Uses a two-pass
    placeholder so swaps (e.g. hwmon3<->hwmon4) don't cascade."""
    placeholders = {}
    new_content = content
    for i, (old, new) in enumerate(renumber.items()):
        ph = f"__FCRENUM_{i}__"
        placeholders[ph] = new
        new_content = re.sub(rf'\b{re.escape(old)}\b', ph, new_content)
    for ph, new in placeholders.items():
        new_content = new_content.replace(ph, new)
    return new_content


def main():
    args = sys.argv[1:]
    quiet = '-q' in args or '--quiet' in args
    apply_changes = '-a' in args or '--apply' in args

    if not apply_changes:
        log("Dry run (use --apply to make changes)", quiet)

    if not os.path.exists(FANCONTROL_FILE):
        log(f"Error: {FANCONTROL_FILE} not found", quiet)
        sys.exit(1)

    old_entries = parse_fancontrol(FANCONTROL_FILE)
    if not old_entries:
        log("Error: no DEVPATH/DEVNAME entries found in fancontrol config", quiet)
        sys.exit(1)

    live = live_hwmon_state()
    mapping, err = resolve_mapping(old_entries, live)
    if err:
        log(f"Error: {err}", quiet)
        sys.exit(1)

    for old_hwmon, info in old_entries.items():
        new_hwmon = mapping[old_hwmon]
        arrow = '' if old_hwmon == new_hwmon else f'  ->  {new_hwmon}'
        log(f"{old_hwmon}: name={info.get('name', '?')} devpath={info.get('devpath', '?')}{arrow}", quiet)

    renumber = {old: new for old, new in mapping.items() if old != new}
    if not renumber:
        log("No changes needed.", quiet)
        sys.exit(0)

    if not apply_changes:
        log(f"Would rewrite {len(renumber)} hwmon assignment(s). Re-run with --apply.", quiet)
        sys.exit(0)

    with open(FANCONTROL_FILE) as f:
        original = f.read()
    updated = rewrite_content(original, renumber)
    with open(FANCONTROL_FILE, 'w') as f:
        f.write(updated)
    log(f"Updated {FANCONTROL_FILE}.", quiet)

    if subprocess.run(["systemctl", "restart", "fancontrol.service"]).returncode != 0:
        log("Error: failed to restart fancontrol.service", quiet)
        sys.exit(1)
    log("Restarted fancontrol.service.", quiet)
    log("Hint: refresh /etc/fancontrol_mappings via 'sudo generate_hwmon_mappings.sh' "
        "so hwmon_mapping_check stops alerting.", quiet)


if __name__ == "__main__":
    main()
