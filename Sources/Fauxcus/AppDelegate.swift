import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var engine: FocusEngine!
    private var panelController: PanelController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKeyManager!
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        store = Store.load()
        engine = FocusEngine(store: store)
        panelController = PanelController(engine: engine, store: store)

        setupStatusItem()

        hotKey = HotKeyManager()
        hotKey.onPress = { [weak self] in self?.summon() }
        hotKey.register(keyCode: Hotkey.keyCode, modifiers: Hotkey.modifiers)
        NotificationCenter.default.addObserver(
            self, selector: #selector(hotkeyChanged),
            name: .hotkeyChanged, object: nil
        )

        panelController.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.appWillTerminate()
    }

    /// Accessory apps have no visible menu bar menus, but ⌘A/⌘C/⌘V/⌘Z are
    /// resolved through the main menu — without an Edit menu they're dead keys.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarImage()

        let menu = NSMenu()
        menu.addItem(makeItem("Show Fauxcus", #selector(showPanel), ""))
        menu.addItem(makeItem("History…", #selector(showHistory), ""))
        menu.addItem(makeItem("Settings…", #selector(showSettings), ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Fauxcus",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    /// Banded-prism template image (1x + 2x reps); alpha-only, so it adapts
    /// to light/dark menu bars. Falls back to an SF Symbol if assets missing.
    private static func menuBarImage() -> NSImage? {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for name in ["MenuBarIcon", "MenuBarIcon@2x"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let rep = NSImageRep(contentsOf: url) {
                rep.size = NSSize(width: 18, height: 18)
                image.addRepresentation(rep)
            }
        }
        guard !image.representations.isEmpty else {
            return NSImage(systemSymbolName: "scope", accessibilityDescription: "Fauxcus")
        }
        image.isTemplate = true
        image.accessibilityDescription = "Fauxcus"
        return image
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showPanel() {
        panelController.show()
    }

    @objc private func showHistory() {
        if historyWindow == nil {
            historyWindow = makeWindow(
                title: "History",
                view: HistoryView().environmentObject(store!)
            )
        }
        present(historyWindow!)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Fauxcus Settings", view: SettingsView())
        }
        present(settingsWindow!)
    }

    private func makeWindow(title: String, view: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func summon() {
        panelController.summon()
        switch engine.phase {
        case .running, .checkIn:
            engine.focusNoteRequest += 1
        case .picker:
            engine.focusTaskRequest += 1
        default:
            break
        }
    }

    @objc private func hotkeyChanged() {
        hotKey.register(keyCode: Hotkey.keyCode, modifiers: Hotkey.modifiers)
    }
}
