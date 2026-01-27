import XCTest
@testable import OurFamilyLedger

/// Tests for Bundle Extensions
final class BundleExtensionsTests: XCTestCase {

    // MARK: - App Version Tests

    func testAppVersion_returnsNonEmptyString() {
        // When
        let version = Bundle.main.appVersion

        // Then
        XCTAssertFalse(version.isEmpty)
    }

    func testAppVersion_matchesExpectedFormat() {
        // When
        let version = Bundle.main.appVersion

        // Then - should match semantic versioning pattern (x.y.z)
        let versionPattern = #"^\d+\.\d+\.\d+$"#
        let regex = try? NSRegularExpression(pattern: versionPattern)
        let range = NSRange(version.startIndex..., in: version)
        let match = regex?.firstMatch(in: version, range: range)

        XCTAssertNotNil(match, "Version '\(version)' should match semantic versioning format")
    }

    // MARK: - Build Number Tests

    func testBuildNumber_returnsNonEmptyString() {
        // When
        let build = Bundle.main.buildNumber

        // Then
        XCTAssertFalse(build.isEmpty)
    }

    func testBuildNumber_isNumeric() {
        // When
        let build = Bundle.main.buildNumber

        // Then
        XCTAssertNotNil(Int(build), "Build number '\(build)' should be a valid integer")
    }

    // MARK: - Full Version String Tests

    func testFullVersionString_containsVersionAndBuild() {
        // When
        let fullVersion = Bundle.main.fullVersionString

        // Then
        XCTAssertTrue(fullVersion.contains("("), "Full version should contain opening parenthesis")
        XCTAssertTrue(fullVersion.contains(")"), "Full version should contain closing parenthesis")
    }

    func testFullVersionString_matchesExpectedFormat() {
        // When
        let fullVersion = Bundle.main.fullVersionString

        // Then - should match "x.y.z (n)" format
        let pattern = #"^\d+\.\d+\.\d+ \(\d+\)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(fullVersion.startIndex..., in: fullVersion)
        let match = regex?.firstMatch(in: fullVersion, range: range)

        XCTAssertNotNil(match, "Full version '\(fullVersion)' should match 'x.y.z (n)' format")
    }

    func testFullVersionString_combinesVersionAndBuild() {
        // When
        let version = Bundle.main.appVersion
        let build = Bundle.main.buildNumber
        let fullVersion = Bundle.main.fullVersionString

        // Then
        let expected = "\(version) (\(build))"
        XCTAssertEqual(fullVersion, expected)
    }
}
