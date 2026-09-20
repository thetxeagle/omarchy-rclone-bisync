# Omarchy Rclone Bisync


[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Read-only Quickshell monitoring for Omarchy user-scoped `rclone bisync` services. It adds a bar
widget with discovered timer health, per-pair results, recent warnings, log and journal shortcuts,
and an interactive review action through Omarchy's configured default coding agent.

## What it does

- Discovers active user timers whose names contain `rclone` or `bisync`.
- Lets you choose which discovered timers to watch from the popup Settings menu.
- Shows whether the watched timers and services are running, healthy, or failed. A completed
  oneshot service is healthy when its timer remains active, and `activating`/`deactivating` are
  treated as running states while a cycle is in progress.
- Distinguishes each watched timer as `SYNCING`, `HEALTHY`, `FAILED`, or `OFF`.
- Shows each watched timer separately, including its service state and last systemd result.
- Summarizes the nine configured pair names from the runner's journal.
- Surfaces recent rclone errors and duplicate-object warnings.
- Groups recent conflict events globally by Drive in the popup.
- Opens the rclone log or systemd journal from the popup.
- Starts a read-only review with `omarchy agent prompt`, following the selected default agent.
- Provides start/stop timer controls.

The widget does not install rclone, configure remotes, run `--resync`, apply a baseline, delete lock
files, or silently grant the AI agent permission to modify anything.

## Requirements

- Omarchy with the Quickshell-based shell.
- Python 3.
- Existing user-scoped rclone/bisync services and timers, such as
  `google-drive-bisync.service` / `google-drive-bisync.timer` and
  `network-bisync.service` / `network-bisync.timer`.
- The runner's default log at `~/.local/state/rclone/google-drive-bisync.log`, unless
  `XDG_STATE_HOME` changes that location.
- A configured Omarchy default agent for the review button:

```bash
omarchy default agent codex
# Or: claude, opencode, gemini, copilot, crush, grok, omp, or pi
```

## Install

Clone the repository, then run the installer as your normal desktop user:

```bash
git clone https://github.com/thetxeagle/omarchy-rclone-bisync.git
cd omarchy-rclone-bisync
./scripts/omarchy/setup-quickshell-rclone-bisync.sh
```

The installer:

1. Copies the plugin into `~/.config/omarchy/plugins/eagle.rclone-bisync/`.
2. Rescans local Quickshell plugins.
3. Places `eagle.rclone-bisync` in the right side of the Omarchy bar.

The shell hot-reloads the plugin. If the icon is not visible, restart only the shell:

```bash
omarchy restart shell
```

## Use the widget

Click the rclone icon in the bar. The popup provides:

- `Refresh` — reread the local status snapshot.
- `Open log` — open the rclone log in Omarchy's default editor.
- `Journal` — open a terminal view of the recent systemd journal.
- `Ask default agent` — launch the configured Omarchy agent with a read-only review prompt.
- `Settings` — discover active rclone/bisync timers and choose which ones the widget watches.
- `Start timer` / `Stop timer` — control the first discovered watched timer.

Timer selections are stored inline in `~/.config/omarchy/shell.json` as the widget's
`watchedTimers` and `watchTimersConfigured` settings. With no saved selection, all discovered
rclone/bisync timers are watched by default.

The status helper is intentionally read-only. It queries `systemctl --user`, reads recent
`journalctl` output, and tails the rclone log; it does not call rclone. Conflict entries are an
index of local log evidence; the recoverable conflict files remain on the Drive archive selected by
the bisync runner.

## Manual checks

```bash
systemctl --user status google-drive-bisync.timer
journalctl --user -u google-drive-bisync.service -n 100 --no-pager
tail -100 ~/.local/state/rclone/google-drive-bisync.log

# Check the SMB timer separately when installed
systemctl --user status network-bisync.timer network-bisync.service
journalctl --user -u network-bisync.service -n 100 --no-pager
tail -100 ~/.local/state/rclone/network-bisync.log
```

The two services may both be enabled, but they serialize access to the shared `~/GoogleDrive`
tree. `SYNCING` means a service is active, activating, or deactivating; `HEALTHY` means the timer
is active and the oneshot service is idle after a successful run; `FAILED` means systemd recorded a
failed service run; and `OFF` means the timer is not active. A failed timer may recover on its next
scheduled run after the underlying issue is fixed.

To test the status payload directly:

```bash
python3 ~/.config/omarchy/plugins/eagle.rclone-bisync/status.py | python3 -m json.tool
```

## Troubleshooting

### The widget is missing from the bar

Run the installer again, then restart the shell:

```bash
./scripts/omarchy/setup-quickshell-rclone-bisync.sh
omarchy restart shell
```

### The panel says `unknown`

Run the status helper manually. If it reports `unknown`, the user bus is unavailable or the
service/timer names differ from this project's expected names.

### The agent button fails

Choose an installed default agent and try again:

```bash
omarchy default agent
omarchy default agent codex
```

The agent opens interactively in a terminal. It is not a background automation job.

## Uninstall

Remove the widget from the bar, then remove its user-owned plugin directory:

```bash
omarchy plugin disable eagle.rclone-bisync
rm -r ~/.config/omarchy/plugins/eagle.rclone-bisync
omarchy restart shell
```

If the move command does not match your current bar layout, remove the `eagle.rclone-bisync` entry
from `~/.config/omarchy/shell.json` and restart the shell. This does not remove rclone, its remotes,
or the bisync service.

## Development

The plugin source lives under `scripts/omarchy/quickshell/eagle.rclone-bisync/`. After editing local
plugin files, copy them into the user plugin directory with the installer or let Omarchy's local
plugin watcher reload them. Validate the non-QML pieces with:

```bash
bash -n scripts/omarchy/setup-quickshell-rclone-bisync.sh
python3 -B scripts/omarchy/quickshell/eagle.rclone-bisync/status.py
jq empty scripts/omarchy/quickshell/eagle.rclone-bisync/manifest.json
```

QML linting depends on the local Omarchy/Quickshell development packages.

## License

MIT. See [LICENSE](LICENSE).
