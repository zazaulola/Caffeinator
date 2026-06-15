import Foundation

final class CaffeinateController {
    private var process: Process?
    private(set) var endDate: Date?

    var onStateChange: (() -> Void)?

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
                    self.onStateChange?()
                }
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            process = nil
            endDate = nil
            NSLog("Caffeinator: failed to start caffeinate: \(error)")
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
        if p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
        process = nil
        endDate = nil
    }
}
