import GoogleMobileAds
import XCTest

@testable import VelocityAdsGmaAdapter

final class VersionNumberParserTests: XCTestCase {

    func test_adapterVersion_foldsAdapterBuildIntoPatch() {
        let version = VersionNumberParser.adapterVersion("0.10.0.0")
        XCTAssertEqual(version.majorVersion, 0)
        XCTAssertEqual(version.minorVersion, 10)
        XCTAssertEqual(version.patchVersion, 0)
    }

    func test_adapterVersion_keepsPatchAndAdapterBuildDistinguishable() {
        let version = VersionNumberParser.adapterVersion("1.2.3.4")
        XCTAssertEqual(version.majorVersion, 1)
        XCTAssertEqual(version.minorVersion, 2)
        XCTAssertEqual(version.patchVersion, 304)
    }

    func test_adapterVersion_withFewerThanFourSegments_yieldsZero() {
        let version = VersionNumberParser.adapterVersion("1.2.3")
        XCTAssertEqual(version.majorVersion, 0)
        XCTAssertEqual(version.minorVersion, 0)
        XCTAssertEqual(version.patchVersion, 0)
    }

    func test_sdkVersion_parsesThreeSegments() {
        let version = VersionNumberParser.sdkVersion("0.10.0")
        XCTAssertEqual(version.majorVersion, 0)
        XCTAssertEqual(version.minorVersion, 10)
        XCTAssertEqual(version.patchVersion, 0)
    }

    func test_sdkVersion_ignoresPreReleaseSuffix() {
        let version = VersionNumberParser.sdkVersion("1.4.2-beta.1")
        XCTAssertEqual(version.majorVersion, 1)
        XCTAssertEqual(version.minorVersion, 4)
        XCTAssertEqual(version.patchVersion, 2)
    }

    func test_sdkVersion_withGarbage_yieldsZero() {
        let version = VersionNumberParser.sdkVersion("unknown")
        XCTAssertEqual(version.majorVersion, 0)
        XCTAssertEqual(version.minorVersion, 0)
        XCTAssertEqual(version.patchVersion, 0)
    }

    func test_adapterReportsItsOwnVersionConstant() {
        let expected = VersionNumberParser.adapterVersion(velocityAdsGmaAdapterVersion)
        let actual = VelocityAdsGmaAdapter.adapterVersion()
        XCTAssertEqual(actual.majorVersion, expected.majorVersion)
        XCTAssertEqual(actual.minorVersion, expected.minorVersion)
        XCTAssertEqual(actual.patchVersion, expected.patchVersion)
    }
}
