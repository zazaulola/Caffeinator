import Foundation

final class CaffeinateController {
    private var process: Process?
    private(set) var endDate: Date?

    var onStateChange: (() -> Void)?
    /// Called on the main queue if launching caffeinate fails.
    var onError: ((Error) -> Void)?

    private static let pidDefaultsKey = "caffeinatePID"

    var isActive: Bool {
        process?.isRunning ?? false
    }

    var remainingSeconds: Int? {
        guard let endDate else { return nil }
        let r = Int(endDate.timeIntervalSinceNow.rounded())
        return r > 0 ? r : nil
    }

    func start(flags: [String], timeoutSeconds: Int?, waitPID: pid_t? = nil) {
        stopSync()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")

        var args = flags
        if let pid = waitPID {
            args.append("-w")
            args.append(String(pid))
            endDate = nil
        } else if let t = timeoutSeconds, t > 0 {
            args.append("-t")
            args.append(String(t))
            endDate = Date().addingTimeInterval(TimeInterval(t))
        } else {
            endDate = nil
        }
        p.arguments = args

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.process === proc {
                    self.process = nil
                    self.endDate = nil
                    Self.clearStoredPID()
                    self.onStateChange?()
                }
            }
        }

        do {
            try p.run()
            process = p
            Self.storePID(p.processIdentifier)
        } catch {
            process = nil
            endDate = nil
            Self.clearStoredPID()
            NSLog("Caffeinator: failed to start caffeinate: \(error)")
            onStateChange?()
            onError?(error)
            return
        }
        onStateChange?()
    }

    func stop() {
        stopSync()
        onStateChange?()
    }

    private func stopSync() {
        guard let p = process else {
            endDate = nil
            return
        }
        p.terminationHandler = nil
        process = nil
        endDate = nil
        Self.clearStoredPID()
        guard p.isRunning else { return }
        // Send SIGTERM synchronously (an instant kill() syscall, so it is
        // delivered even if we exit right after), but reap the child off the
        // main thread so toggling/quitting never blocks the UI run loop.
        p.terminate()
        DispatchQueue.global(qos: .utility).async {
            p.waitUntilExit()
        }
    }

    // MARK: - Orphan reaping (crash / force-quit safety net)

    private static func storePID(_ pid: pid_t) {
        UserDefaults.standard.set(Int(pid), forKey: pidDefaultsKey)
    }

    private static func clearStoredPID() {
        UserDefaults.standard.removeObject(forKey: pidDefaultsKey)
    }

    /// If a previous run was killed (crash, SIGKILL, force-quit) before it could
    /// stop caffeinate, that child keeps the Mac awake with no UI to stop it.
    /// On launch, terminate such an orphan — but only after confirming the
    /// stored PID still maps to /usr/bin/caffeinate, so a recycled PID is safe.
    static func reapOrphanIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: pidDefaultsKey)
        guard stored > 0 else { return }
        clearStoredPID()
        let pid = pid_t(stored)
        if executablePath(of: pid) == "/usr/bin/caffeinate" {
            kill(pid, SIGTERM)
        }
    }

    /// Absolute executable path of a live PID, or nil if the PID is dead or
    /// inaccessible. (proc_pidpath fails for non-existent processes.)
    private static func executablePath(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }
}
