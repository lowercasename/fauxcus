# Fauxcus

A tiny, native macOS focus companion that keeps one task name in your peripheral vision, heals itself when you drift or walk away, and never makes you feel bad.

Fauxcus lives as a small floating panel in the corner of your desktop plus a menu bar item — no Dock icon, no ⌘-Tab entry. You tell it what you're working on; it keeps you gently pointed at that one thing.

## Design principles

Every decision in Fauxcus follows one standing constraint, ADHD-first:

- **Self-healing over punitive.** Walk away, forget to pause, quit mid-task — the app quietly fixes the books. Your focus time is never inflated and never lost.
- **No guilt states.** No streaks, no daily totals, no red timers, no "you were gone 40 minutes!". Comparison metrics curdle into guilt on bad days, so they don't exist.
- **The desired action is always the cheapest action.** Returning to work is one click. Ignoring a check-in is a legitimate answer. Resolving a stale task is one tap.
- **Fixed opinionated defaults.** No interval sliders, no settings sprawl. When a default is wrong, the default gets changed — a knob doesn't get added.

## The loop

- **Start** — one field: "What are you working on?" Enter starts a count-up timer. Parked tasks are listed below as one-tap resumes; quiet autocomplete draws on your task history.
- **Breath** — at the midpoint of each check-in interval, the panel takes a slow, silent 2-second breath to re-anchor your attention on the task name.
- **Check-in** — "Still on *X*?" with Yes / Pausing. Never a modal, never a sound, never steals focus. Ignore it for 60 seconds and it assumes you're working. The interval backs off 10 → 15 → 20 → 25 minutes as you confirm, and resets on a new task.
- **Walk-away** — after 5 minutes of system idle (or sleep), the task auto-pauses **backdated to when you left**. Coming back shows a calm one-click Resume. Away time never counts.
- **Pause** — Take a break / Park this task / Back to task.
- **Break** — count-up, task stays loaded, one big "Back to it". A gentle nudge at 10 minutes, again every 5. No countdowns, no escalation.
- **Park** — write a breadcrumb ("Where did you leave off?"), task moves to the parked list. Hard cap of **5 parked tasks**: parking a 6th asks you to migrate one first — to **Todoist**, **Apple Reminders**, **Things**, or the clipboard as Markdown.
- **Done** — a brief completion flourish with the task name and focused time, then back to the picker.
- **History** — a plain, stats-free list of everything you've finished or migrated, with notes and Markdown copy-out.

## Notes

Each task has one running notes field — always showing the full history, saving as you type. The ✎ button (or the global hotkey mid-task) opens it; the park screen pre-loads it so your breadcrumb lands in context.

## Controls

- **Global hotkey ⌃⌥Space** (rebindable in Settings) summons the panel: straight into note capture when a task is running, into the task field when idle.
- The panel floats above other windows, never takes focus except when you deliberately type, is draggable anywhere, and remembers its spot.
- Settings contains exactly three things: the hotkey, launch at login, and a Todoist API token.

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

Everything lives in a single human-readable JSON file at
`~/Library/Application Support/Fauxcus/store.json`. A 30-second heartbeat
makes crash recovery lossless: on the next launch, an interrupted task is
closed at the last heartbeat and parked.

---

Inspired by [Focana](https://focana.app)'s concept and [Things](https://culturedcode.com/things/)' feel. Built with Claude Code.
