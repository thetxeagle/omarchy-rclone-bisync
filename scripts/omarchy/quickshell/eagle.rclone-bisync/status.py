#!/usr/bin/env python3

"""Emit bounded, read-only status for the Omarchy Google Drive bisync job."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
from datetime import datetime
import sys


UNIT = "google-drive-bisync.service"
TIMER = "google-drive-bisync.timer"
LOG_PATH = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "rclone/google-drive-bisync.log"
PAIRS = [
    "gdrive",
    "Obsidian Vault",
    "gdrive-3d-printing",
    "gdrive-company-files",
    "gdrive-frank-storage",
    "gdrive-graphics",
    "gdrive-programming",
    "gdrive-public-files",
    "gdrive-software",
]


def run(*args: str) -> str:
    try:
        result = subprocess.run(
            list(args), check=False, capture_output=True, text=True, timeout=3
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.strip()


def state(unit: str) -> str:
    return run("systemctl", "--user", "is-active", unit) or "unknown"


def active_timers() -> list[str]:
    """Find active user timers that look like rclone/bisync jobs."""
    lines = run(
        "systemctl", "--user", "list-units", "--type=timer", "--state=active",
        "--no-legend", "--no-pager", "--plain"
    ).splitlines()
    return [
        line.split()[0]
        for line in lines
        if line.split() and line.split()[0].endswith(".timer")
        and re.search(r"(?:rclone|bisync)", line.split()[0], re.IGNORECASE)
    ]


def timer_service(timer: str) -> str:
    return run("systemctl", "--user", "show", timer, "-p", "Unit", "--value") or timer.removesuffix(".timer") + ".service"


def service_result(service: str) -> str:
    return run("systemctl", "--user", "show", service, "-p", "Result", "--value") or "unknown"


def configured_timers() -> tuple[list[str], bool]:
    try:
        raw = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
    except (TypeError, ValueError, json.JSONDecodeError):
        raw = {}
    if isinstance(raw, dict):
        values = raw.get("timers", [])
        configured = raw.get("configured", False) is True
    else:
        values = raw
        configured = bool(values)
    if not isinstance(values, list):
        values = []
    return ([str(timer) for timer in values if isinstance(timer, str) and timer.endswith(".timer")], configured)


def timer_rows(selected: list[str], configured: bool) -> list[dict[str, str | bool]]:
    discovered = active_timers()
    units = discovered + [timer for timer in selected if timer not in discovered]
    default_selected = not configured
    rows = []
    for timer in units:
        service = timer_service(timer)
        timer_state = state(timer)
        service_state = state(service)
        if service_state in {"active", "activating", "deactivating"}:
            status_label = "SYNCING"
        elif service_state == "failed":
            status_label = "FAILED"
        elif timer_state == "active":
            status_label = "HEALTHY"
        else:
            status_label = "OFF"
        rows.append({
            "timer": timer,
            "service": service,
            "timerState": timer_state,
            "serviceState": service_state,
            "result": service_result(service),
            "status": status_label,
            "watched": default_selected or timer in selected,
            "active": timer in discovered,
        })
    return rows


def tail(path: Path, lines: int = 240) -> list[str]:
    try:
        return path.read_text(errors="replace").splitlines()[-lines:]
    except OSError:
        return []


def parse_pairs(journal: list[str]) -> list[dict[str, str]]:
    latest: dict[str, dict[str, str]] = {
        pair: {"name": pair, "state": "unknown"} for pair in PAIRS
    }
    for line in journal:
        match = re.search(r"google-drive-bisync\[\d+\]: (.+)$", line)
        if not match:
            continue
        message = match.group(1)
        if message.startswith("Starting bisync: "):
            name = message.removeprefix("Starting bisync: ").split(" <->", 1)[0].rstrip(":")
            state_name = "running"
        elif message.startswith("Completed: "):
            name = message.removeprefix("Completed: ").rstrip(":")
            state_name = "ok"
        elif message.startswith("FAILED: "):
            name = message.removeprefix("FAILED: ").split(" (exit", 1)[0].rstrip(":")
            state_name = "failed"
        else:
            continue

        if name.startswith("gdrive:Obsidian Vaults/"):
            key = "Obsidian Vault"
        else:
            key = name
        if key in latest:
            latest[key] = {"name": key, "state": state_name}
    return list(latest.values())


def parse_conflicts(log: list[str]) -> list[dict[str, str]]:
    """Extract recent conflict events from the local rclone log."""
    conflicts: list[dict[str, str]] = []
    drive = "Unknown drive"
    for line in log:
        sync_match = re.search(r'Synching Path1 ".*?" with Path2 "([^"{]+)', line)
        if sync_match:
            remote = sync_match.group(1).rstrip(":")
            drive = "Obsidian Vault" if "Obsidian Vaults/" in remote else remote
        if not re.search(r"(?i)(conflict|\.conflict\d+|rclone-conflict)", line):
            continue
        timestamp = line[:19]
        detail = line[20:].strip() if len(line) > 20 else line.strip()
        conflicts.append({"drive": drive, "timestamp": timestamp, "detail": detail})
    return conflicts[-20:]


def main() -> None:
    selected, selection_configured = configured_timers()
    timers = timer_rows(selected, selection_configured)
    watched = [row for row in timers if row["watched"]]
    active_watched = [row for row in watched if row["active"]]
    aggregate_timer = "active" if active_watched and len(active_watched) == len(watched) else "inactive"
    # A oneshot service normally becomes inactive after a successful run. That is healthy as long
    # as its timer remains active; only an explicit failed service should mark the aggregate failed.
    service_states = [str(row["serviceState"]) for row in watched]
    aggregate_service = "failed" if "failed" in service_states else (
        "active" if any(state_name in {"active", "activating", "deactivating"} for state_name in service_states)
        else "inactive"
    )
    journal = run("journalctl", "--user", "-u", UNIT, "--no-pager", "-n", "240").splitlines()
    log = tail(LOG_PATH)
    recent_errors = [line.strip() for line in log if " ERROR " in line or "FAILED:" in line][-5:]
    recent_warnings = [line.strip() for line in log if "Duplicate object" in line or "WARNING" in line][-5:]
    last_success = next((line.strip() for line in reversed(log) if "Bisync successful" in line), "")
    last_timestamp = ""
    for line in reversed(log):
        match = re.match(r"(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", line)
        if match:
            try:
                last_timestamp = datetime.strptime(match.group(1), "%Y/%m/%d %H:%M:%S").isoformat(sep=" ")
            except ValueError:
                pass
            break

    result = {
        "timer": aggregate_timer,
        "service": aggregate_service,
        "timers": timers,
        "watchedTimers": [row["timer"] for row in watched],
        "logPath": str(LOG_PATH),
        "journalUnit": UNIT,
        "lastLogTime": last_timestamp,
        "lastSuccess": last_success,
        "errors": recent_errors,
        "warnings": recent_warnings,
        "conflicts": parse_conflicts(log),
        "pairs": parse_pairs(journal),
    }
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
