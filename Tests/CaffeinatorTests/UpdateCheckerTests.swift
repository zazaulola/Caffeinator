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
}
