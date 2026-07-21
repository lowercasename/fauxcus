# Fauxcus

A macOS focus helper and task buddy: a small always-on-top panel showing the current task name and a count-up timer. Tasks can be parked for later, at which point Fauxcus prompts you for some notes to help you pick it back up. When a task is running, Fauxcus intermittently checks in on your progress to help nudge you back to the task, or encourage you to take a genuine break (breaks are important!)

https://github.com/user-attachments/assets/d1e3770a-bc56-4794-92e2-06dac1ab8e04

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

---

Inspired by [Focana](https://focana.app) and [Things](https://culturedcode.com/things/). Built with Claude Code.
