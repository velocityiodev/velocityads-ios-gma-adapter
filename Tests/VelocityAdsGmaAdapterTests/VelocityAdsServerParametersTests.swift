import XCTest

@testable import VelocityAdsGmaAdapter

final class VelocityAdsServerParametersTests: XCTestCase {

    func test_parse_fullJSON_yieldsAppKeyAndAdUnitId() {
        let parsed = VelocityAdsServerParameters.parse(#"{"appKey":"app-123","adUnitId":"unit-abc"}"#)
        XCTAssertEqual(parsed.appKey, "app-123")
        XCTAssertEqual(parsed.adUnitId, "unit-abc")
    }

    func test_parse_JSONWithOnlyAdUnitId_yieldsNilAppKey() {
        let parsed = VelocityAdsServerParameters.parse(#"{"adUnitId":"unit-abc"}"#)
        XCTAssertNil(parsed.appKey)
        XCTAssertEqual(parsed.adUnitId, "unit-abc")
    }

    func test_parse_JSONWithBlankValues_normalisesToNil() {
        let parsed = VelocityAdsServerParameters.parse(#"{"appKey":"   ","adUnitId":""}"#)
        XCTAssertNil(parsed.appKey)
        XCTAssertNil(parsed.adUnitId)
    }

    func test_parse_toleratesWhitespaceAndUnknownKeys() {
        let parsed = VelocityAdsServerParameters.parse(#"  {"adUnitId":"unit-abc","appKey":"app-123","extra":1}  "#)
        XCTAssertEqual(parsed.appKey, "app-123")
        XCTAssertEqual(parsed.adUnitId, "unit-abc")
    }

    func test_parse_nonStringValues_areIgnored() {
        let parsed = VelocityAdsServerParameters.parse(#"{"adUnitId":42,"appKey":true}"#)
        XCTAssertEqual(parsed, .empty)
    }

    func test_parse_bareString_isTreatedAsAdUnitId() {
        let parsed = VelocityAdsServerParameters.parse("  unit-abc ")
        XCTAssertNil(parsed.appKey)
        XCTAssertEqual(parsed.adUnitId, "unit-abc")
    }

    func test_parse_malformedJSON_yieldsEmpty() {
        XCTAssertEqual(VelocityAdsServerParameters.parse(#"{"adUnitId": "#), .empty)
        XCTAssertEqual(VelocityAdsServerParameters.parse("{not json}"), .empty)
    }

    func test_parse_nilOrBlank_yieldsEmpty() {
        XCTAssertEqual(VelocityAdsServerParameters.parse(nil), .empty)
        XCTAssertEqual(VelocityAdsServerParameters.parse(""), .empty)
        XCTAssertEqual(VelocityAdsServerParameters.parse("   "), .empty)
    }
}
