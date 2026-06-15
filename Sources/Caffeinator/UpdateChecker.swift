import Foundation

enum UpdateResult {
    case upToDate(current: String)
    case updateAvailable(latest: String, url: URL)
    case failed(String)
}

/// Checks GitHub Releases for a newer version of Caffeinator.
final class UpdateChecker {
    static let repo = "zazaulola/Caffeinator"
    private static let lastCheckKey = "lastUpdateCheck"

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    var releasesPageURL: URL {
        URL(string: "https://github.com/\(Self.repo)/releases")!
    }

    /// Runs a check at most once per `minInterval`. Used for the silent
    /// on-launch check so we never hammer the API.
    func checkIfDue(minInterval: TimeInterval = 24 * 60 * 60,
                    completion: @escaping (UpdateResult) -> Void) {
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < minInterval {
            return
        }
        check(completion: completion)
    }

    /// Always performs a check. Completion is delivered on the main queue.
    func check(completion: @escaping (UpdateResult) -> Void) {
        let current = currentVersion
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else {
            finish(completion, .failed("Invalid update URL"))
            return
        }

        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Caffeinator", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }

            if let error = error {
                self.finish(completion, .failed(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                self.finish(completion, .failed("No response from GitHub"))
                return
            }
            // No releases published yet → nothing is newer than what we run.
            if http.statusCode == 404 {
                self.finish(completion, .upToDate(current: current))
                return
            }
            guard http.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                self.finish(completion, .failed("Unexpected response from GitHub (\(http.statusCode))"))
                return
            }

            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? self.releasesPageURL
            if Self.isNewer(tag, than: current) {
                self.finish(completion, .updateAvailable(latest: Self.clean(tag), url: page))
            } else {
                self.finish(completion, .upToDate(current: current))
            }
        }.resume()
    }

    private func finish(_ completion: @escaping (UpdateResult) -> Void, _ result: UpdateResult) {
        DispatchQueue.main.async { completion(result) }
    }

    // MARK: - Version comparison

    /// Strips a leading "v"/"V" from a tag like "v1.2.0".
    static func clean(_ version: String) -> String {
        var s = version.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        return s
    }

    /// True if `tag` represents a version strictly newer than `current`.
    static func isNewer(_ tag: String, than current: String) -> Bool {
        compare(clean(tag), clean(current)) > 0
    }

    /// Numeric, component-wise comparison: -1 / 0 / 1. Non-numeric junk in a
    /// component is treated as 0, and missing trailing components as 0, so
    /// "1.2" == "1.2.0" and "1.2.1" > "1.2".
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = parts(a)
        let pb = parts(b)
        for i in 0..<Swift.max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(separator: ".").map { comp in
            Int(comp.prefix(while: { $0.isNumber })) ?? 0
        }
    }
}
