import AppKit
import Carbon.HIToolbox
import DisplaySplitCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private lazy var tiler = Tiler(settings: settings)
    private lazy var windowObserver = WindowObserver { [weak self] window in
        guard let self, settings.load().config.centerNewWindows else { return }
        tiler.place(window, in: .center)
    }
    private let hotKeys = HotKeys()
    private var statusItem: NSStatusItem?
    private var trustPollTimer: Timer?

    private static let hotKeyModifiers = controlKey | optionKey
    private static let columnHotKeys: [(column: Column, title: String, keyCode: Int, menuKey: Int)] = [
        (.left, "Left", kVK_LeftArrow, NSLeftArrowFunctionKey),
        (.center, "Center", kVK_UpArrow, NSUpArrowFunctionKey),
        (.right, "Right", kVK_RightArrow, NSRightArrowFunctionKey),
    ]

    func applicationDidFinishLaunching(_: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "DisplaySplit")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        for hotKey in Self.columnHotKeys {
            hotKeys.register(keyCode: hotKey.keyCode, modifiers: Self.hotKeyModifiers) { [weak self] in
                self?.tiler.moveFocusedWindow(to: hotKey.column)
            }
        }

        do {
            try settings.createIfMissing()
        } catch {
            NSLog("DisplaySplit: could not create \(settings.fileURL.path): \(error)")
        }

        if AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            windowObserver.start()
        } else {
            // Permission is granted in System Settings while we run; start as soon as it lands.
            trustPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                MainActor.assumeIsolated { self?.windowObserver.start() }
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !AXIsProcessTrusted() {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let loaded = settings.load()
        if let error = loaded.error {
            // Refuse menu edits while the file is broken: saving would overwrite the user's text.
            let problem = item("Config Error: \(error)", #selector(openConfigFile))
            problem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(problem)
            menu.addItem(.separator())
        }

        let auto = item("Center New Windows", loaded.error == nil ? #selector(toggleCenterNewWindows) : nil)
        auto.state = loaded.config.centerNewWindows ? .on : .off
        menu.addItem(auto)
        menu.addItem(item("Column Split \(loaded.config.split)…", loaded.error == nil ? #selector(editSplit) : nil))
        menu.addItem(item("Open Config File", #selector(openConfigFile)))

        menu.addItem(.separator())
        for (index, hotKey) in Self.columnHotKeys.enumerated() {
            // Key equivalents here are display-only; the global hotkeys do the work.
            let move = item("Move Window \(hotKey.title)", #selector(moveFocusedWindow(_:)),
                            key: String(Character(UnicodeScalar(hotKey.menuKey)!)))
            move.keyEquivalentModifierMask = [.control, .option]
            move.tag = index
            menu.addItem(move)
        }
        menu.addItem(item("Center All Windows", #selector(centerAllWindows)))

        menu.addItem(.separator())
        menu.addItem(item("Quit DisplaySplit", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    @objc private func toggleCenterNewWindows() {
        var config = settings.load().config
        config.centerNewWindows.toggle()
        save(config)
    }

    private func save(_ config: Config) {
        do {
            try settings.save(config)
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openConfigFile() {
        NSWorkspace.shared.open(settings.fileURL)
    }

    @objc private func editSplit() {
        let previousApp = NSWorkspace.shared.frontmostApplication
        var config = settings.load().config
        let field = NSTextField(string: config.split.description)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        field.placeholderString = ColumnSplit.default.description

        let alert = NSAlert()
        alert.messageText = "Column Split"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let hint = "Relative widths left:center:right, e.g. 1:2:1 or 1:3:2."
        alert.informativeText = hint

        // A menu bar app is never active on its own; without this the dialog opens behind windows.
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            if let split = ColumnSplit(field.stringValue) {
                config.split = split
                save(config)
                break
            }
            alert.informativeText = "“\(field.stringValue)” is not three positive numbers.\n\(hint)"
        }
        // Hand focus back so the move hotkeys act on the window the user was in.
        previousApp?.activate()
    }

    @objc private func moveFocusedWindow(_ sender: NSMenuItem) {
        // The menu is ours, but focus stays with the previously active app's window.
        tiler.moveFocusedWindow(to: Self.columnHotKeys[sender.tag].column)
    }

    @objc private func centerAllWindows() {
        tiler.centerAllWindows()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
