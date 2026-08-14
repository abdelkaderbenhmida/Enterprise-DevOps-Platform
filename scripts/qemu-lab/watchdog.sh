#!/usr/bin/env bash
# scripts/qemu-lab/watchdog.sh — keeps the 25-VM run alive.
# Restarts qemu-lab.sh all (resumable via work/run-progress.txt) until done.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPT_DIR/work/run.log"
LOCK="$SCRIPT_DIR/work/runner.lock"
WORK="$SCRIPT_DIR/work"
mkdir -p "$WORK"

cleanup() { rm -f "$LOCK"; }
trap cleanup EXIT

while true; do
  if [[ ! -f "$LOCK" ]]; then
    touch "$LOCK"
    echo "$(date '+%F %T') watchdog: launching run" >> "$LOG"
    "$SCRIPT_DIR/qemu-lab.sh" all >> "$LOG" 2>&1
    cleanup
    if grep -q "ALL VMs done" "$LOG"; then
      echo "$(date '+%F %T') watchdog: ALL VMs done" >> "$LOG"
      exit 0
    fi
    echo "$(date '+%F %T') watchdog: run exited, restarting" >> "$LOG"
  fi
  sleep 60
done