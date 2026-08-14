#!/usr/bin/env python3
"""Dynamic Ansible inventory: delegates to scripts/generate-inventory.py

Usage (as Ansible inventory script):
    ansible -i inventory/dynamic_inventory.py <host-pattern> -m ping

Supports the standard dynamic inventory contracts:
    --list   -> JSON inventory with _meta.hostvars
    --host h -> hostvars for host h
Default (no args) -> INI rendering of the same inventory.
"""
import json
import subprocess
import sys
from pathlib import Path

GENERATOR = Path(__file__).resolve().parent.parent.parent / "scripts" / "generate-inventory.py"


def run_generator(args=None):
    cmd = [sys.executable, str(GENERATOR)] + (args or [])
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return result.stdout


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--list":
        print(run_generator(["--list"]))
    elif len(sys.argv) > 1 and sys.argv[1] == "--host":
        print(json.dumps({}))
    else:
        print(run_generator())


if __name__ == "__main__":
    main()