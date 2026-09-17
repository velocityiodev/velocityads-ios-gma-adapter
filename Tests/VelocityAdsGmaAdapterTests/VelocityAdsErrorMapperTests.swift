import GoogleMobileAds
import VelocityAdsSDK
import XCTest

@testable import VelocityAdsGmaAdapter

/// Covers every constant in `VelocityAdsErrorCode` plus the unknown-code fallback. Each
/// mapping must preserve the Velocity code and message so they stay visible in Ad
/// Inspector and logs.
final class VelocityAdsErrorMapperTests: XCTestCase {

    private let testMessage = "test message"

    private func assertMapping(_ velocityCode: Int, to category: RequestError.Code,
                               file: StaticString = #filePath, line: UInt = #line) {
        let mapped = VelocityAdsErrorMapper.map(VelocityAdsError(code: velocityCode, message: testMessage))
        XCTAssertEqual(mapped.domain, VelocityAdsErrorMapper.sdkDomain, file: file, line: line)
        XCTAssertEqual(mapped.code, category.rawValue, "GMA category code must match", file: file, line: line)
        XCTAssertEqual(mapped.localizedDescription, "Velocity Ads [\(velocityCode)]: \(testMessage)", file: file, line: line)
        XCTAssertEqual(mapped.userInfo[VelocityAdsErrorMapper.velocityErrorCodeKey] as? Int, velocityCode,
                       "Velocity code must be preserved verbatim", file: file, line: line)
        let underlying = mapped.userInfo[NSUnderlyingErrorKey] as? NSError
        XCTAssertEqual(underlying?.domain, VelocityAdsErrorMapper.sdkDomain, file: file, line: line)
        XCTAssertEqual(underlying?.code, velocityCode, file: file, line: line)
        XCTAssertEqual(underlying?.localizedDescription, testMessage, "Velocity message must be preserved verbatim",
                       file: file, line: line)
    }

    // MARK: - No fill

    func test_noFill_mapsToNoFill() {
        assertMapping(VelocityAdsErrorCode.noFill, to: .noFill)
    }

    // MARK: - Network

    func test_networkLayerCodes_mapToNetworkError() {
        assertMapping(VelocityAdsErrorCode.networkError, to: .networkError)
        assertMapping(VelocityAdsErrorCode.httpFailure, to: .networkError)
        assertMapping(VelocityAdsErrorCode.serverErrorField, to: .networkError)
    }

    // MARK: - Invalid request / state

    func test_configurationAndStateCodes_mapToInvalidRequest() {
        assertMapping(VelocityAdsErrorCode.invalidURL, to: .invalidRequest)
        assertMapping(VelocityAdsErrorCode.invalidAppKey, to: .invalidRequest)
        assertMapping(VelocityAdsErrorCode.invalidAdUnitId, to: .invalidRequest)
        assertMapping(VelocityAdsErrorCode.sdkNotInitialized, to: .invalidRequest)
        assertMapping(VelocityAdsErrorCode.sdkInitializationInProgress, to: .invalidRequest)
        assertMapping(VelocityAdsErrorCode.loadAlreadyInProgress, to: .invalidRequest)
        assertMapping(VelocityAdsErrorCode.adAlreadyLoaded, to: .invalidRequest)
        assertMapping(VelocityAdsErrorCode.adSpent, to: .invalidRequest)
        assertMapping(VelocityAdsErrorCode.adDestroyed, to: .invalidRequest)
    }

    // MARK: - Internal

    func test_parseResponseAndInternalCodes_mapToInternalError() {
        assertMapping(VelocityAdsErrorCode.jsonParseError, to: .internalError)
        assertMapping(VelocityAdsErrorCode.invalidResponse, to: .internalError)
        assertMapping(VelocityAdsErrorCode.emptyResponseBody, to: .internalError)
        assertMapping(VelocityAdsErrorCode.invalidAdResponse, to: .internalError)
        assertMapping(VelocityAdsErrorCode.loadServiceUnavailable, to: .internalError)
        assertMapping(VelocityAdsErrorCode.waterfallLoadFailed, to: .internalError)
        assertMapping(VelocityAdsErrorCode.internalError, to: .internalError)
    }

    func test_unknownCode_mapsToInternalError() {
        assertMapping(-1, to: .internalError)
        assertMapping(9999, to: .internalError)
    }

    // MARK: - Adapter-originated errors

    func test_adapterErrors_useAdapterDomainAndHaveNoUnderlyingError() {
        let cases: [(NSError, VelocityAdsErrorMapper.AdapterErrorCode)] = [
            (VelocityAdsErrorMapper.invalidServerParameters(), .invalidServerParameters),
            (VelocityAdsErrorMapper.sdkNotInitialized(), .sdkNotInitialized),
            (VelocityAdsErrorMapper.adNotReady(), .adNotReady),
            (VelocityAdsErrorMapper.invalidAdSize("fluid"), .invalidAdSize),
            (VelocityAdsErrorMapper.adapterReleased(), .adapterReleased)
        ]
        for (error, expected) in cases {
            XCTAssertEqual(error.domain, VelocityAdsErrorMapper.adapterDomain)
            XCTAssertEqual(error.code, expected.rawValue)
            XCTAssertNil(error.userInfo[NSUnderlyingErrorKey])
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
