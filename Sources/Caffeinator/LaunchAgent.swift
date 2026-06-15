import Foundation

enum LaunchAgent {
    static let label = "com.caffeinator.menubar"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func install() throws {
        let executablePath = try resolveExecutablePath()

        let plist: [String: Any] = [
            "Label":            label,
            "ProgramArguments": [executablePath],
            "RunAtLoad":        true,
            "KeepAlive":        false,
            "ProcessType":      "Interactive",
        ]

        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        // Best-effort: register with launchd for the current session as well.
        // Failures are non-fatal — the plist will be picked up on next login.
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        _ = run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    static func uninstall() throws {
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func resolveExecutablePath() throws -> String {
        if let path = Bundle.main.executablePath {
            return path
        }
        throw NSError(
            domain: "Caffeinator",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to resolve app executable path."]
        )
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }
}
