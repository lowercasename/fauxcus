# Fauxcus

A macOS focus tracker: a small always-on-top panel showing the current task name and a count-up timer, plus a menu bar item. Runs as an accessory app (no Dock icon).

## Design constraints

- Timing self-corrects. Idle, sleep, crashes, and forgotten pauses are reconciled automatically, so recorded focus time stays accurate without user discipline.
- No streaks, daily totals, or overdue indicators anywhere in the UI.
- Fixed defaults. Settings contains only the global hotkey, launch at login, and a Todoist API token.

## Behaviour

- **Start**: enter a task name to start a count-up timer. Parked tasks are listed for one-click resume; autocomplete draws on task history.
- **Check-in**: the panel periodically asks "Still on *X*?" (Yes / Pausing) — never a modal, sound, or focus steal. Ignored for 60 seconds counts as Yes. The interval backs off 10 → 15 → 20 → 25 minutes on consecutive confirms and resets on a new task. At each interval's midpoint the panel plays a 2-second scale animation to draw the eye to the task name.
- **Idle**: after 5 minutes of system idle or sleep, the task auto-pauses, backdated to when the idle began.
- **Pause**: break (count-up timer, reminder at 10 minutes then every 5), park, or resume.
- **Park**: prompts for a note on where you left off. Parked list is capped at 5; parking a 6th requires migrating one out to Todoist, Apple Reminders, Things, or the clipboard as Markdown.
- **Done**: completed and migrated tasks land in a plain history list with notes and Markdown copy-out. No aggregate stats.

Each task has one autosaving notes field, opened with the ✎ button or the global hotkey mid-task; the park screen pre-loads it.

## Controls

- Global hotkey ⌃⌥Space (rebindable): opens note capture when a task is running, the task field when idle.
- The panel floats above other windows, takes keyboard focus only while you type, and is draggable; position persists.

## Building

Requirements: macOS 14+, Xcode (Swift 6 toolchain). [Inkscape](https://inkscape.org) is only needed if you regenerate icons.

```sh
./build.sh          # build ad-hoc signed build/Fauxcus.app
./build.sh install  # build, install to /Applications, and relaunch
```

Icons are generated from the SVG sources in `Resources/icon/`:

```sh
./scripts/generate-icons.sh
```

## Data

Everything lives in a single JSON file at `~/Library/Application Support/Fauxcus/store.json`. A 30-second heartbeat makes crash recovery lossless: on the next launch, an interrupted task is closed at the last heartbeat and parked.

---

Inspired by [Focana](https://focana.app) and [Things](https://culturedcode.com/things/). Built with Claude Code.
