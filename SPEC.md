# Fauxcus — Specification

The detailed contract for how Fauxcus behaves. The README is the overview; this is the reference. When behavior and this document disagree, one of them is a bug.

**One sentence:** A tiny, native, menu-bar macOS companion that keeps one task name in your peripheral vision, heals itself when you drift or walk away, and never makes you feel bad.

## Standing design constraint

ADHD-first. Every decision, present and future, is tested against these four rules:

1. **Self-healing over punitive.** The system reconciles idle time, sleep, crashes, and forgotten pauses on its own. Accuracy never depends on user diligence.
2. **No guilt states.** No streaks, daily totals, overdue markers, red timers, or "you were gone N minutes" messaging. Comparison metrics are banned.
3. **The desired action is always the cheapest action.** Returning to work, resuming a parked task, resolving a stale one — each is one click. Ignoring a prompt is always a legitimate answer.
4. **Fixed opinionated defaults.** No cadence sliders or behavior toggles. Wrong defaults get changed in code, not exposed as settings.

## Platform & presence

- Native SwiftUI + AppKit. Swift Package (`swift build`) + `build.sh` assembles and ad-hoc signs `Fauxcus.app`; `build.sh install` replaces `/Applications/Fauxcus.app` and relaunches. macOS 14+.
- **Menu bar accessory** (`LSUIElement`): no Dock icon, no ⌘-Tab entry. Menu bar item (banded-prism template icon) with: Show Fauxcus / History… / Settings… / Quit.
- **The panel** is a borderless, non-activating `NSPanel` (300pt wide, height fits content):
  - Floats above all windows (`.floating`), joins all Spaces and full-screen apps.
  - Never steals focus except when the user deliberately types (nonactivating panel becomes key only for text entry).
  - Draggable by its background; position persists across launches, clamped fully on-screen (a saved off-screen position self-heals on next launch, and the panel re-clamps live when displays are added or removed).
  - Grows upward from its bottom-left anchor when content expands (bottom edge re-pinned on resize).
  - Liquid Glass surface (`.glassEffect(.regular)`) on macOS 26+, with the frosted `NSVisualEffectView` (`.popover`) as the pre-Tahoe fallback; 16pt continuous-corner radius, spring animations between states (response 0.35, damping 0.8). Clicking the running timer's digits previews the sheen wave.
- An invisible main menu provides the Edit key equivalents (⌘A/⌘C/⌘V/⌘X/⌘Z/⇧⌘Z) that accessory apps otherwise lack.
- Launch at login via `SMAppService`, enabled automatically on the very first launch, toggleable in Settings (failures revert the toggle and explain themselves inline).

## Task model

- **Statuses:** `active` (at most one), `parked`, `completed`, `migrated`.
- **No to-do list.** The only forward-looking store is the parked list.
- **Parked tasks:** hard cap of **5**. Never expire. Parking a 6th opens the migration screen ("Parking's full — migrate one to make room"); freeing a slot (migrate or delete) completes the pending park automatically.
- **History:** append-only list of completed and migrated tasks. No stats, no editing.
- **Autocomplete:** the picker suggests a task name from full history (case-insensitive prefix match, most recent first, min 2 chars typed); clicking the suggestion fills the field.
- **Deletion:** parked tasks (⋯ menu, parking-full screen) and history rows can be deleted. Always confirmed via an NSAlert: names the task, warns when notes will be lost, "This can't be undone.", destructive red **Delete**, **Cancel** holds the Return key, Escape cancels. Deletion removes the record entirely — it does not go to history.

## Notes model

- One running text blob per task. All notes surfaces edit the same blob with full history visible.
- **Live-saving:** every keystroke updates the in-memory record; disk writes debounce at 0.5s. There is no save button and no way to lose an edit (pause/complete/quit all flush).
- The editor is a fixed-height (88pt) `TextEditor` with an aligned ghost placeholder; on focus the insertion point jumps to the end of existing notes, scrolled visible.
- Surfaces: running view (✎ button or global hotkey; placeholder "Notes for this task…"), park screen (pre-loaded; placeholder "Where did you leave off?"). Resume rows show the last non-empty line as a breadcrumb teaser.

## State machine

Phases: `picker`, `running`, `checkIn`, `pauseMenu`, `switchNote`, `onBreak`, `away`, `completion`, `parkingFull`.

There is no onboarding phase: the very first launch quietly enables start-at-login (reversible in Settings) and opens straight into the picker.

- `picker` → (Enter on non-empty field | tap parked row) → `running`.
- `running` → check-in timer → `checkIn`; Done → `completion`; Pause → `pauseMenu`; idle/sleep → `away`.
- `checkIn` → Yes or 60s timeout → `running` (backoff advances); Pause → `pauseMenu`; idle/sleep → `away`.
- `pauseMenu` (session already closed): Take a break → `onBreak`; Park this task → `switchNote`; Back to task → `running` (new session, backoff resets).
- `switchNote`: Park it → `picker` (or `parkingFull` if at cap); Back → `pauseMenu`.
- `onBreak`: Back to it → `running` (new session, backoff resets). Idle rules suspended during breaks; sleeping while on break stays on break.
- `away`: Resume → `running` (new session, backoff resets); Done → `completion`; Park this task → `switchNote`.
- `completion`: auto-advances to `picker` after the flourish.
- `parkingFull`: migrate/delete one → pending park completes → `picker`; Never mind → `pauseMenu`.
- App termination with an active task: session closed at quit, task parked (cap may temporarily exceed 5 — enforced only at explicit park).

## Timings (fixed in code)

| Constant | Value |
|---|---|
| Check-in intervals | 10 → 15 → 20 → 25 min (advance on Yes or timeout; reset on new task/resume) |
| Check-in ignore timeout | 60 s (counts as Yes) |
| Breath | midpoint of current interval, once per interval (also fires on check-in entry and each break nudge) |
| Idle auto-pause threshold | 5 min of zero system input (any device), or system sleep |
| Idle backdating | session end = now − idle seconds (never counts away time) |
| Break nudges | first at 10 min, repeat every 5 min |
| Completion flourish | 1.8 s, then picker |
| Store heartbeat | every 30 s while running or awaiting a check-in |
| Notes save debounce | 0.5 s |

## Animations

- **Breath** (FYI tier): 2-second brighten-and-settle (scale 1.04, brightness +0.07) on the task name / break header. Silent, non-interactive.
- **Sheen wave** (needs-an-answer tier): a 16°-tilted band of accent-colored light (opacity 0.14 → 0.28 crest → 0.14, no white core, no hard edges) sweeps the whole panel in 2.2 s, twice (second pass at +2.6 s). Fires on check-in entry and each break nudge. Respects Reduce Motion (wave suppressed entirely).
- Completion flourish: spring-in checkmark (accent), task name, focused duration. No streak/aggregate copy.

## Vocabulary

Five verbs, used identically everywhere: tasks are **parked** (with a breadcrumb), **resumed**, **migrated** (Todoist / Reminders / Things / clipboard), **completed**, **deleted**. "Switch" was retired — the park flow's menu item is "Park this task", commit button "Park it".

Park screen copy: eyebrow = task name (10pt semibold uppercase, kerned, truncated), title "Leave a breadcrumb", subtitle "Next steps, resources, or reminders for future you."

## Migrations

Destinations (parked ⋯ menu and parking-full screen; Things hidden unless installed):

- **Todoist** — `POST https://api.todoist.com/api/v1/tasks` (unified v1 API; REST v2 is dead, returns 410), Bearer token from Settings, name → `content`, notes → `description`.
- **Apple Reminders** — EventKit full access (one-time TCC prompt; `NSRemindersFullAccessUsageDescription` in Info.plist), default reminders list, notes attached.
- **Things** — `things:///add?title=…&notes=…` URL scheme; availability probed via `NSWorkspace.urlForApplication`. Opening activates Things (inherent to URL schemes).
- **Copy to clipboard & clear** — Markdown block (name, started, focused duration, status, notes).

Migrated tasks keep their record (status `migrated`, destination stamped) and appear in history ("Migrated to X" / "Copied to clipboard").

## Error handling

- **Recoverable errors are inline, never modal** (NSAlert steals focus — forbidden for anything the user didn't initiate). Migration failures show a dismissible warning banner (yellow triangle, ✕) in the picker and parking-full screens.
- Errors are distinguished by cause:
  - Todoist 401/403: "Todoist rejected the token — check it in Settings."
  - Network failure: "Couldn't reach Todoist — check your connection and try again."
  - 429: "Todoist asked for a breather — try again in a minute."
  - Other HTTP: "Todoist had a problem (error N) — try again."
  - Reminders access denied: points to System Settings → Privacy & Security → Reminders.
  - Reminders no default list: points to the Reminders app's settings.
  - Things missing: "Things doesn't seem to be installed."
- **User-initiated destructive actions** (delete) are the one sanctioned modal: HIG-style confirmation alert (see Task model).

## Controls

- **Global hotkey** default ⌃⌥Space (Carbon `RegisterEventHotKey` — no accessibility permission needed). Summons the panel; focuses note capture when running, the task field when idle. Rebindable in Settings via an inline recorder (requires ≥1 modifier; Escape cancels recording). Every hotkey action has full mouse parity.
- **Settings** (window): hotkey recorder, launch-at-login toggle, Todoist API token (stored in UserDefaults). Nothing else, by design.
- The picker's task field is an AppKit-backed `NSTextField` (SwiftUI's plain TextField shifts its text when the field editor swaps in on focus).

## Icon system

Three variants from SVG sources in `Resources/icon/`, regenerated by `scripts/generate-icons.sh` (Inkscape):

- **App icon** (`appicon.svg` → `Fauxcus.icns`, all sizes to 1024): prism on a light squircle plate; frameless "liquid glass" style — six hard spectrum bands (macOS system colors, parallel to the right face's base) with a frosted white wash (0.85→0.6) over the left facet. Faces are indicated by light, not linework.
- **Inline glyph** (`inline.svg` → `PrismIcon.png` 18/36): simplified four-band version of the same frost treatment; prefixes the picker's task field, Things-style.
- **Menu bar** (`menubar.svg` → `MenuBarIcon.png` 18/36): **template image** (alpha-only, adapts to menu bar appearance). Keeps the black frame + divider + alternating solid/clear bands — at 18pt a frameless template dissolves into floating chips, so the outline stays here by rule.
- `prism.svg` is the standalone framed artwork the app icon originally derived from.

## Data

`~/Library/Application Support/Fauxcus/store.json` — single human-readable JSON payload `{ tasks: [TaskRecord], heartbeat: Date }`, ISO-8601 dates, atomic writes.

`TaskRecord`: id, name, createdAt, sessions (start/end pairs; focused time = sum), notes, status, parkedAt, completedAt, exportedTo.

Crash healing on load: any `active` task with an open session gets the session closed at the last heartbeat and is parked. Focused time is never inflated by a crash and never lost beyond 30 s.

Storage failures are never silent: if `store.json` exists but can't be read, it is moved aside as `store.corrupt-<timestamp>.json` (never overwritten) and the panel shows a warning; if disk writes start failing, a persistent banner says so until a save succeeds.

UserDefaults: first-run flag, panel origin, hotkey code/modifiers, Todoist token.

## Architecture (file map)

- `main.swift`, `AppDelegate.swift` — app bootstrap, status item, Edit menu, hotkey wiring, aux windows.
- `Engine/FocusEngine.swift` — the state machine, all timers/cadences, migrations; `Engine/IdleMonitor.swift` — system idle seconds.
- `Models/Models.swift` — `TaskRecord`/`TaskSession`; `Models/Store.swift` — persistence, queries, heartbeat, healing.
- `UI/FloatingPanel.swift` — panel + positioning; `UI/PanelRootView.swift` — phase router, background, breath/wave effects; `UI/PhaseViews.swift` — all panel states; `UI/PlainTextField.swift` — AppKit text field; `UI/HistoryView.swift`, `UI/SettingsView.swift`.
- `Support/` — Format (clock/duration), Markdown export, Carbon hotkey, login item; `Integrations/` — Todoist, Reminders, Things.

## Testing

`swift test` covers the model transitions, store persistence (roundtrip, crash healing, corrupt-file backup), the engine state machine (check-in cadence and backoff, idle backdating, breaks, the parking cap and pending-park completion), and the formatters. The engine takes injectable `dateNow`/`idleSecondsProvider` closures so tests drive time deterministically. `swift test` needs the full Xcode toolchain (`xcode-select -p` should point at Xcode, not the Command Line Tools).

## Out of scope (deliberately cut)

Stats/charts, streaks, Pomodoro modes, multiple timers, iCloud sync, iOS companion, calendar integration, website/app blocking, sounds, onboarding of any kind, to-do lists.

## Known loose ends

- Ad-hoc signature changes each rebuild → Reminders TCC may re-prompt after updates. Fix: free Apple ID development certificate.
- Todoist token in UserDefaults plain text → move to Keychain eventually.
- Launch-at-login registers the running copy's path — re-toggle after the app moved to `/Applications`.
