import GoogleMobileAds
import VelocityAdsSDK
import XCTest

@testable import VelocityAdsGmaAdapter

/// Tests for `VelocityAdsGmaAdapter.resolveBannerSize(_:)`, which maps the Google Mobile
/// Ads `AdSize` onto the Velocity banner size the SDK is asked to fill.
final class BannerSizeResolutionTests: XCTestCase {

    // MARK: - IAB presets

    func test_banner_mapsToBannerPreset() {
        XCTAssertEqual(VelocityAdsGmaAdapter.resolveBannerSize(AdSizeBanner), .banner)
    }

    func test_mediumRectangle_mapsToMrecPreset() {
        XCTAssertEqual(VelocityAdsGmaAdapter.resolveBannerSize(AdSizeMediumRectangle), .mrec)
    }

    func test_leaderboard_mapsToLeaderboardPreset() {
        XCTAssertEqual(VelocityAdsGmaAdapter.resolveBannerSize(AdSizeLeaderboard), .leaderboard)
    }

    // MARK: - Concrete non-preset sizes

    func test_otherFixedIABSizes_areForwardedAsCustomSizes() {
        XCTAssertEqual(VelocityAdsGmaAdapter.resolveBannerSize(AdSizeLargeBanner), .custom(width: 320, height: 100))
        XCTAssertEqual(VelocityAdsGmaAdapter.resolveBannerSize(AdSizeFullBanner), .custom(width: 468, height: 60))
    }

    func test_arbitraryCGSize_isForwardedAsCustomSize() {
        let size = VelocityAdsGmaAdapter.resolveBannerSize(adSizeFor(cgSize: CGSize(width: 360, height: 56)))
        XCTAssertEqual(size, .custom(width: 360, height: 56))
    }

    func test_anchoredAdaptive_isForwardedWithItsResolvedDimensions() {
        // Anchored adaptive sizes are concrete once created — the Google Mobile Ads SDK
        // resolves the height from the width and orientation.
        let adaptive = largePortraitAnchoredAdaptiveBanner(width: 375)
        let expected = cgSize(for: adaptive)
        XCTAssertGreaterThan(expected.height, 0, "Precondition: anchored adaptive resolves a concrete height")
        XCTAssertEqual(
            VelocityAdsGmaAdapter.resolveBannerSize(adaptive),
            .custom(width: expected.width, height: expected.height)
        )
    }

    func test_inlineAdaptiveWithMaxHeight_isForwardedWithItsDimensions() {
        let inline = inlineAdaptiveBanner(width: 320, maxHeight: 200)
        let expected = cgSize(for: inline)
        XCTAssertEqual(
            VelocityAdsGmaAdapter.resolveBannerSize(inline),
            .custom(width: expected.width, height: expected.height)
        )
    }

    // MARK: - Unsupported sizes

    func test_fluid_isRejected() {
        XCTAssertNil(VelocityAdsGmaAdapter.resolveBannerSize(AdSizeFluid))
    }

    func test_invalid_isRejected() {
        XCTAssertNil(VelocityAdsGmaAdapter.resolveBannerSize(AdSizeInvalid))
    }

    func test_zeroDimensions_areRejected() {
        XCTAssertNil(VelocityAdsGmaAdapter.resolveBannerSize(adSizeFor(cgSize: CGSize(width: 320, height: 0))))
        XCTAssertNil(VelocityAdsGmaAdapter.resolveBannerSize(adSizeFor(cgSize: CGSize(width: 0, height: 50))))
    }
}
