import XCTest
@testable import Caffeinator

final class UpdateCheckerVersionTests: XCTestCase {

    // MARK: isNewer — the decision that drives the update banner

    func testNewerVersionsDetected() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.1", than: "1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("v2.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("V3", than: "2.9"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("v1.0", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))   // trailing zeros
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2"))
    }

    func testOlderVersionsAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.9", than: "2.0"))
    }

    /// The classic trap: lexical comparison would say "1.10" < "1.9".
    func testNumericNotLexicalComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.21", than: "1.3"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9", than: "1.10"))
    }

    /// Tags with pre-release / build suffixes parse by their numeric prefix.
    func testSuffixesIgnoredPerComponent() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.2.0-beta", than: "1.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0-beta", than: "1.2"))
    }

    // MARK: clean

    func testCleanStripsLeadingVAndWhitespace() {
        XCTAssertEqual(UpdateChecker.clean("v1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateChecker.clean("V1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateChecker.clean("  v1.0 "), "1.0")
        XCTAssertEqual(UpdateChecker.clean("1.0"), "1.0")
    }

    // MARK: compare contract (-1 / 0 / 1)

    func testCompareReturnsOrdering() {
        XCTAssertEqual(UpdateChecker.compare("1.0", "1.0"), 0)
        XCTAssertEqual(UpdateChecker.compare("2.0", "1.0"), 1)
        XCTAssertEqual(UpdateChecker.compare("1.0", "2.0"), -1)
        XCTAssertEqual(UpdateChecker.compare("1.0.0", "1.0"), 0)
    }

    // MARK: non-network surface

    func testReleasesPageURL() {
        XCTAssertEqual(
            UpdateChecker().releasesPageURL.absoluteString,
            "https://github.com/zazaulola/Caffeinator/releases"
        )
    }

    func testCurrentVersionIsNonEmpty() {
        XCTAssertFalse(UpdateChecker().currentVersion.isEmpty)
    }

    // MARK: isValidVersion — reject non-version tags (dates, "latest", hashes)

    func testValidVersionsAccepted() {
        XCTAssertTrue(UpdateChecker.isValidVersion("1"))
        XCTAssertTrue(UpdateChecker.isValidVersion("1.2"))
        XCTAssertTrue(UpdateChecker.isValidVersion("1.2.3"))
    }

    func testNonVersionTagsRejected() {
        XCTAssertFalse(UpdateChecker.isValidVersion(""))
        XCTAssertFalse(UpdateChecker.isValidVersion("latest"))
        XCTAssertFalse(UpdateChecker.isValidVersion("2024-06-01"))   // date-style
        XCTAssertFalse(UpdateChecker.isValidVersion("1.2-beta"))     // suffix
        XCTAssertFalse(UpdateChecker.isValidVersion("v1.2"))         // expects cleaned input
    }

    // MARK: isTrustedReleaseURL — only https github.com may be opened

    func testTrustedReleaseURLs() {
        XCTAssertTrue(UpdateChecker.isTrustedReleaseURL(
            URL(string: "https://github.com/zazaulola/Caffeinator/releases/tag/v1.2")!))
    }

    func testUntrustedReleaseURLsRejected() {
        XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(URL(string: "http://github.com/x")!))   // not https
        XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(URL(string: "https://evil.example/x")!)) // wrong host
        XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(URL(string: "file:///etc/passwd")!))     // file scheme
    }
}
