import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let controller = CaffeinateController()
    private let defaults = UserDefaults.standard

    private var stateItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var modeDisplayItem: NSMenuItem!
    private var modeIdleItem: NSMenuItem!
    private var modeDiskItem: NSMenuItem!
    private var modeSystemItem: NSMenuItem!
    private var timerSubmenu: NSMenu!
    private var watchItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!

    private var watchedPID: pid_t?
    private var watchedName: String = ""
    private var picker: ProcessPickerWindowController?

    private let power = PowerMonitor()
    private var lastPower: PowerMonitor.Snapshot?
    private static let lowBatteryThreshold = 10  // percent

    private let updater = UpdateChecker()
    private var updateItem: NSMenuItem!
    private var updateSeparator: NSMenuItem!
    private var checkUpdatesItem: NSMenuItem!
    private var updateURL: URL?

    private let kModeDisplay = "modeDisplay"
    private let kModeIdle    = "modeIdle"
    private let kModeDisk    = "modeDisk"
    private let kModeSystem  = "modeSystem"
    private let kTimer       = "timerSeconds"

    private let timerPresets: [(label: String, seconds: Int)] = [
        ("Until I turn it off", 0),
        ("15 minutes",          15 * 60),
        ("30 minutes",          30 * 60),
        ("1 hour",              60 * 60),
        ("2 hours",             2 * 60 * 60),
        ("4 hours",             4 * 60 * 60),
        ("8 hours",             8 * 60 * 60),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [
            kModeDisplay: true,
            kModeIdle:    false,
            kModeDisk:    false,
            kModeSystem:  false,
            kTimer:       0,
        ])

        buildStatusItem()
        controller.onStateChange = { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }

        power.onChange = { [weak self] snap in
            self?.handlePowerChange(snap)
        }
        power.start()
        lastPower = power.snapshot()

        refresh()

        // Silent, rate-limited update check (at most once a day). Only surfaces
        // the menu item when something newer is actually available.
        updater.checkIfDue { [weak self] result in
            if case let .updateAvailable(latest, url) = result {
                self?.showUpdateAvailable(version: latest, url: url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
        power.stop()
    }

    // MARK: - Battery guard

    private func handlePowerChange(_ snap: PowerMonitor.Snapshot) {
        lastPower = snap
        if shouldForceDisable(snap), controller.isActive {
            controller.stop()
        }
        refresh()
    }

    private func shouldForceDisable(_ snap: PowerMonitor.Snapshot) -> Bool {
        snap.hasBattery
            && snap.isOnBattery
            && snap.percentage <= Self.lowBatteryThreshold
    }

    // MARK: - Menu construction

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        updateItem = NSMenuItem(title: "Update available",
                                action: #selector(openUpdate),
                                keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)

        updateSeparator = .separator()
        updateSeparator.isHidden = true
        menu.addItem(updateSeparator)

        stateItem = NSMenuItem(title: "Your Mac sleeps normally", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        toggleItem = NSMenuItem(title: "Keep my Mac awake", action: #selector(toggleAction), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Keep awake"))

        modeDisplayItem = makeModeItem(title: "The screen", key: kModeDisplay)
        menu.addItem(modeDisplayItem)

        modeIdleItem = makeModeItem(title: "The system, even when idle", key: kModeIdle)
        menu.addItem(modeIdleItem)

        modeDiskItem = makeModeItem(title: "Storage (good for backups, downloads)", key: kModeDisk)
        menu.addItem(modeDiskItem)

        modeSystemItem = makeModeItem(title: "Never sleep while plugged in", key: kModeSystem)
        menu.addItem(modeSystemItem)

        menu.addItem(.separator())

        timerSubmenu = NSMenu()
        let selected = defaults.integer(forKey: kTimer)
        for preset in timerPresets {
            let it = NSMenuItem(title: preset.label, action: #selector(setTimer(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = preset.seconds
            it.state = (preset.seconds == selected) ? .on : .off
            timerSubmenu.addItem(it)
        }
        let timerItem = NSMenuItem(title: "Turn off after…", action: nil, keyEquivalent: "")
        timerItem.submenu = timerSubmenu
        menu.addItem(timerItem)

        watchItem = NSMenuItem(title: "Until an app or task finishes…",
                               action: #selector(pickWatchProcess),
                               keyEquivalent: "")
        watchItem.target = self
        menu.addItem(watchItem)

        menu.addItem(.separator())

        launchAtLoginItem = NSMenuItem(title: "Open when I log in",
                                       action: #selector(toggleLaunchAtLogin),
                                       keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = LaunchAgent.isInstalled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        checkUpdatesItem = NSMenuItem(title: "Check for Updates…",
                                      action: #selector(checkForUpdates),
                                      keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        let about = NSMenuItem(title: "About Caffeinator", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Caffeinator", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    private func makeModeItem(title: String, key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: #selector(toggleMode(_:)), keyEquivalent: "")
        it.target = self
        it.representedObject = key
        it.state = defaults.bool(forKey: key) ? .on : .off
        return it
    }

    // MARK: - Actions

    @objc private func toggleAction() {
        if controller.isActive {
            controller.stop()
        } else if let snap = lastPower, shouldForceDisable(snap) {
            return
        } else {
            startWithCurrentSettings()
        }
    }

    @objc private func pickWatchProcess() {
        if let snap = lastPower, shouldForceDisable(snap) { return }
        if picker == nil {
            picker = ProcessPickerWindowController()
        }
        picker?.onPick = { [weak self] proc in
            guard let self, let proc else { return }
            self.watchedPID = proc.pid
            self.watchedName = proc.name
            self.startWithCurrentSettings()
        }
        picker?.show()
    }

    @objc private func toggleMode(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        let newValue = sender.state != .on
        defaults.set(newValue, forKey: key)
        sender.state = newValue ? .on : .off
        if controller.isActive {
            startWithCurrentSettings()
        }
    }

    @objc private func setTimer(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        defaults.set(seconds, forKey: kTimer)
        for it in timerSubmenu.items {
            if let s = it.representedObject as? Int {
                it.state = (s == seconds) ? .on : .off
            }
        }
        // Selecting a timer cancels any active process watch.
        watchedPID = nil
        watchedName = ""
        if controller.isActive {
            startWithCurrentSettings()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let shouldInstall = !LaunchAgent.isInstalled()
        do {
            if shouldInstall {
                try LaunchAgent.install()
            } else {
                try LaunchAgent.uninstall()
            }
            launchAtLoginItem.state = LaunchAgent.isInstalled() ? .on : .off
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't change the login setting"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func checkForUpdates() {
        checkUpdatesItem.isEnabled = false
        checkUpdatesItem.title = "Checking for updates…"
        updater.check { [weak self] result in
            guard let self else { return }
            self.checkUpdatesItem.isEnabled = true
            self.checkUpdatesItem.title = "Check for Updates…"

            let alert = NSAlert()
            switch result {
            case let .updateAvailable(latest, url):
                self.showUpdateAvailable(version: latest, url: url)
                alert.messageText = "A new version is available"
                alert.informativeText = "Caffeinator \(latest) is available. "
                    + "You're running \(self.updater.currentVersion)."
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(url)
                }
            case let .upToDate(current):
                alert.messageText = "You're up to date"
                alert.informativeText = "Caffeinator \(current) is the latest version."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            case let .failed(message):
                alert.alertStyle = .warning
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = message
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func showUpdateAvailable(version: String, url: URL) {
        updateURL = url
        updateItem.title = "✨ Update available: \(version)"
        updateItem.isHidden = false
        updateSeparator.isHidden = false
    }

    @objc private func openUpdate() {
        if let url = updateURL {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(updater.releasesPageURL)
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Caffeinator"
        alert.informativeText = """
            Caffeinator stops your Mac from falling asleep when you need it to stay awake — long downloads, video calls, presentations, file transfers, renders, anything that takes a while.

            Pick what to keep awake (the screen, the system, storage), set how long, or have it wait until a specific app or task finishes. When you turn it off, your Mac goes back to sleeping normally.

            To save power, Caffeinator turns itself off if your battery drops below 10 % while unplugged.
            """
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func startWithCurrentSettings() {
        let flags = currentFlags()
        if let pid = watchedPID {
            controller.start(flags: flags, timeoutSeconds: nil, waitPID: pid)
        } else {
            let t = defaults.integer(forKey: kTimer)
            controller.start(flags: flags, timeoutSeconds: t > 0 ? t : nil)
        }
    }

    private func currentFlags() -> [String] {
        var flags: [String] = []
        if defaults.bool(forKey: kModeDisplay) { flags.append("-d") }
        if defaults.bool(forKey: kModeIdle)    { flags.append("-i") }
        if defaults.bool(forKey: kModeDisk)    { flags.append("-m") }
        if defaults.bool(forKey: kModeSystem)  { flags.append("-s") }
        if flags.isEmpty { flags.append("-d") }
        return flags
    }

    private func refresh() {
        let active = controller.isActive
        let snap = lastPower
        let forceDisabled = snap.map(shouldForceDisable) ?? false

        if !active {
            watchedPID = nil
            watchedName = ""
        }

        let symbol = active ? "cup.and.saucer.fill" : "cup.and.saucer"
        let desc   = active ? "Keeping your Mac awake" : "Your Mac sleeps normally"
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: desc) {
            img.isTemplate = true
            statusItem.button?.image = img
        }

        if active {
            if !watchedName.isEmpty {
                stateItem.title = "Awake while \(watchedName) is running"
                toggleItem.title = "Let my Mac sleep"
            } else if let remaining = controller.remainingSeconds {
                stateItem.title = "Awake · \(formatDuration(remaining)) left"
                toggleItem.title = "Let my Mac sleep"
            } else {
                stateItem.title = "Keeping your Mac awake"
                toggleItem.title = "Let my Mac sleep"
            }
        } else if forceDisabled, let snap {
            stateItem.title = "Off — saving battery (\(snap.percentage)% left)"
            toggleItem.title = "Keep my Mac awake"
        } else {
            stateItem.title = "Your Mac sleeps normally"
            toggleItem.title = "Keep my Mac awake"
        }

        toggleItem.isEnabled = active || !forceDisabled
        watchItem?.isEnabled = !forceDisabled
        watchItem?.title = (active && watchedPID != nil)
            ? "Wait for a different app or task…"
            : "Until an app or task finishes…"
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "less than a minute" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 {
            if m == 0 { return h == 1 ? "1 hour" : "\(h) hours" }
            return "\(h) h \(m) min"
        }
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }
}
