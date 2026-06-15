import AppKit

struct RunningProcess: Equatable {
    let pid: pid_t
    let name: String
    let path: String?
    let icon: NSImage?
    let isApp: Bool
}

final class ProcessPickerWindowController: NSWindowController,
                                            NSTableViewDataSource,
                                            NSTableViewDelegate,
                                            NSSearchFieldDelegate,
                                            NSWindowDelegate {

    var onPick: ((RunningProcess?) -> Void)?

    private var allProcesses: [RunningProcess] = []
    private var filtered: [RunningProcess] = []
    private var includeBackground = false
    private var didFinish = false

    private let searchField = NSSearchField()
    private let tableView   = NSTableView()
    private let scrollView  = NSScrollView()
    private let backgroundCheckbox = NSButton()
    private let watchButton   = NSButton()
    private let cancelButton  = NSButton()

    private static let cellID = NSUserInterfaceItemIdentifier("ProcessCell")

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Wait for an app or task"
        win.isReleasedWhenClosed = false
        super.init(window: win)
        win.delegate = self
        win.center()
        layoutContent()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Public entry

    func show() {
        didFinish = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        refreshProcessList()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    // MARK: - Layout

    private func layoutContent() {
        guard let win = window else { return }
        let content = NSView()
        win.contentView = content

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search by name"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(handleWatch)
        content.addSubview(searchField)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        content.addSubview(scrollView)

        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.doubleAction = #selector(handleWatch)
        tableView.style = .inset
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        scrollView.documentView = tableView

        backgroundCheckbox.translatesAutoresizingMaskIntoConstraints = false
        backgroundCheckbox.setButtonType(.switch)
        backgroundCheckbox.title = "Show background tasks too"
        backgroundCheckbox.target = self
        backgroundCheckbox.action = #selector(toggleBackground)
        content.addSubview(backgroundCheckbox)

        watchButton.translatesAutoresizingMaskIntoConstraints = false
        watchButton.title = "Wait for this"
        watchButton.bezelStyle = .rounded
        watchButton.keyEquivalent = "\r"
        watchButton.target = self
        watchButton.action = #selector(handleWatch)
        watchButton.isEnabled = false
        content.addSubview(watchButton)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(handleCancel)
        content.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scrollView.bottomAnchor.constraint(equalTo: backgroundCheckbox.topAnchor, constant: -12),

            backgroundCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            backgroundCheckbox.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: watchButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

            watchButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            watchButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            watchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])
    }

    // MARK: - Data

    /// Rebuilds the process list and refreshes the table. GUI apps come from
    /// NSWorkspace (main thread, cheap); the optional `ps` enumeration of every
    /// process runs off the main thread so it never freezes the UI.
    private func refreshProcessList() {
        let apps = guiApps()
        if includeBackground {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let background = self?.listAllProcesses() ?? []
                DispatchQueue.main.async {
                    guard let self, !self.didFinish else { return }
                    self.allProcesses = self.merged(apps: apps, background: background)
                    self.applyFilter()
                }
            }
        } else {
            allProcesses = merged(apps: apps, background: [])
            applyFilter()
        }
    }

    private func guiApps() -> [RunningProcess] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid > 0 else { return nil }
            return RunningProcess(
                pid: pid,
                name: app.localizedName ?? app.bundleIdentifier ?? "PID \(pid)",
                path: app.bundleURL?.path ?? app.executableURL?.path,
                icon: app.icon,
                isApp: true
            )
        }
    }

    /// Merges GUI apps over background processes (apps win on PID collision),
    /// drops our own PID, and sorts apps-first then by name.
    private func merged(apps: [RunningProcess], background: [RunningProcess]) -> [RunningProcess] {
        var byPID: [pid_t: RunningProcess] = [:]
        for entry in background { byPID[entry.pid] = entry }
        for app in apps { byPID[app.pid] = app }
        byPID.removeValue(forKey: Foundation.ProcessInfo.processInfo.processIdentifier)
        return byPID.values.sorted { lhs, rhs in
            if lhs.isApp != rhs.isApp { return lhs.isApp }
            let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return lhs.pid < rhs.pid
        }
    }

    private func listAllProcesses() -> [RunningProcess] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,comm="]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return []
        }
        // Drain stdout BEFORE waiting: reading to EOF unblocks ps as it writes
        // and returns once ps closes the pipe (exits), so it can't deadlock on a
        // full pipe buffer the way wait-then-read would.
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let str = String(data: data, encoding: .utf8) else { return [] }

        var result: [RunningProcess] = []
        for raw in str.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " ") else { continue }
            let pidStr = String(line[..<space])
            let cmd = String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            guard let pid = pid_t(pidStr), pid > 0, !cmd.isEmpty else { continue }
            let name = (cmd as NSString).lastPathComponent
            result.append(RunningProcess(pid: pid, name: name, path: cmd, icon: nil, isApp: false))
        }
        return result
    }

    private func applyFilter() {
        let previousPID: pid_t? = {
            let row = tableView.selectedRow
            guard row >= 0, row < filtered.count else { return nil }
            return filtered[row].pid
        }()

        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        if query.isEmpty {
            filtered = allProcesses
        } else {
            filtered = allProcesses.filter { p in
                if p.name.lowercased().contains(query) { return true }
                if String(p.pid).contains(query) { return true }
                if let path = p.path?.lowercased(), path.contains(query) { return true }
                return false
            }
        }
        tableView.reloadData()

        if let pid = previousPID,
           let newIdx = filtered.firstIndex(where: { $0.pid == pid }) {
            tableView.selectRowIndexes(IndexSet(integer: newIdx), byExtendingSelection: false)
            tableView.scrollRowToVisible(newIdx)
        }
        updateWatchButtonState()
    }

    private func updateWatchButtonState() {
        watchButton.isEnabled = tableView.selectedRow >= 0 && tableView.selectedRow < filtered.count
    }

    // MARK: - Actions

    @objc private func toggleBackground() {
        includeBackground = backgroundCheckbox.state == .on
        refreshProcessList()
    }

    @objc private func handleWatch() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        finish(with: filtered[row])
    }

    @objc private func handleCancel() {
        finish(with: nil)
    }

    private func finish(with proc: RunningProcess?) {
        if didFinish { return }
        didFinish = true
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        onPick?(proc)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        finish(with: nil)
    }

    // MARK: - NSSearchFieldDelegate / NSControlTextEditingDelegate

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            window?.makeFirstResponder(tableView)
            if tableView.selectedRow == -1, !filtered.isEmpty {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                tableView.scrollRowToVisible(0)
            }
            return true
        }
        return false
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateWatchButtonState()
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let cell: ProcessCellView
        if let reused = tableView.makeView(withIdentifier: Self.cellID, owner: self) as? ProcessCellView {
            cell = reused
        } else {
            cell = ProcessCellView()
            cell.identifier = Self.cellID
        }
        cell.configure(with: filtered[row])
        return cell
    }
}

// MARK: - Cell view

final class ProcessCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let pidLabel  = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        addSubview(nameLabel)

        pathLabel.font = NSFont.systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.isBezeled = false
        pathLabel.drawsBackground = false
        addSubview(pathLabel)

        pidLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        pidLabel.textColor = .secondaryLabelColor
        pidLabel.translatesAutoresizingMaskIntoConstraints = false
        pidLabel.alignment = .right
        pidLabel.isBezeled = false
        pidLabel.drawsBackground = false
        addSubview(pidLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: pidLabel.leadingAnchor, constant: -8),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),

            pidLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pidLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pidLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
    }

    func configure(with proc: RunningProcess) {
        nameLabel.stringValue = proc.name
        pathLabel.stringValue = proc.path ?? ""
        pidLabel.stringValue = String(proc.pid)
        if let icon = proc.icon {
            iconView.image = icon
        } else {
            let symbol = proc.isApp ? "app" : "terminal"
            iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }
}
