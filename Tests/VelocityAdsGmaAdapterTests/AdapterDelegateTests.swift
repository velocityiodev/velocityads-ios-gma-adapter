import GoogleMobileAds
import UIKit
import VelocityAdsSDK
import XCTest

@testable import VelocityAdsGmaAdapter

// MARK: - Event delegate spies

/// Records every Google Mobile Ads event-delegate call in order so tests can assert both
/// the translation and the ordering of Velocity callbacks.
private class EventSpy: NSObject, MediationAdEventDelegate {
    var events: [String] = []
    var presentError: NSError?

    func reportImpression() { events.append("impression") }
    func reportClick() { events.append("click") }
    func willPresentFullScreenView() { events.append("willPresent") }
    func didFailToPresentWithError(_ error: Error) {
        events.append("failToPresent")
        presentError = error as NSError
    }
    func willDismissFullScreenView() { events.append("willDismiss") }
    func didDismissFullScreenView() { events.append("didDismiss") }
}

private final class InterstitialEventSpy: EventSpy, MediationInterstitialAdEventDelegate {
    func willBackgroundApplication() { events.append("background") }
}

private final class RewardedEventSpy: EventSpy, MediationRewardedAdEventDelegate {
    func didRewardUser() { events.append("reward") }
    func didStartVideo() { events.append("videoStart") }
    func didEndVideo() { events.append("videoEnd") }
}

private final class BannerEventSpy: EventSpy, MediationBannerAdEventDelegate {
    func willBackgroundApplication() { events.append("background") }
}

// MARK: - Fixtures

private func makeInterstitial() -> VelocityInterstitialAd {
    VelocityInterstitialAd(VelocityInterstitialAdRequest.Builder(adUnitId: "unit-1").build())
}

private func makeRewarded() -> VelocityRewardedAd {
    VelocityRewardedAd(VelocityRewardedAdRequest.Builder(adUnitId: "unit-1").build())
}

@MainActor
private func makeBanner() -> (VelocityBannerAd, VelocityBannerAdView) {
    let request = VelocityBannerAdRequest.Builder(adUnitId: "unit-1", adSize: .banner).build()
    return (VelocityBannerAd(request), VelocityBannerAdView(frame: CGRect(x: 0, y: 0, width: 320, height: 50)))
}

private let sdkError = VelocityAdsError(code: VelocityAdsErrorCode.noFill, message: "no fill")

// MARK: - Interstitial

/// Tests for the Velocity → Google Mobile Ads translation performed by the per-format
/// delegates and the ad classes that own them. The Velocity ads are never loaded; the
/// tests drive the delegate callbacks directly, exactly as the SDK would.
@MainActor
final class VelocityInterstitialAdapterDelegateTests: XCTestCase {

    private var completions: [(any MediationInterstitialAd)?] = []
    private var errors: [NSError?] = []
    private var finished = 0
    private var spy = InterstitialEventSpy()

    private func makeAd() -> VelocityGmaInterstitialAd {
        spy = InterstitialEventSpy()
        let ad = VelocityGmaInterstitialAd(ad: makeInterstitial()) { [weak self] mediationAd, error in
            self?.completions.append(mediationAd)
            self?.errors.append(error as NSError?)
            return self?.spy
        }
        ad.onAdFinished = { [weak self] in self?.finished += 1 }
        return ad
    }

    func test_onAdLoaded_handsTheAdToGoogleAndCapturesTheEventDelegate() {
        let ad = makeAd()
        ad.delegate?.onAdLoaded(ad: makeInterstitial())

        XCTAssertEqual(completions.count, 1)
        XCTAssertTrue(completions.first! === ad)
        XCTAssertNil(errors.first!)
        XCTAssertTrue(ad.delegate?.eventDelegate === spy)
    }

    func test_onAdFailedToLoad_reportsMappedErrorOnceAndReleasesTheCreative() {
        let ad = makeAd()
        ad.delegate?.onAdFailedToLoad(ad: makeInterstitial(), error: sdkError)
        ad.delegate?.onAdFailedToLoad(ad: makeInterstitial(), error: sdkError)

        XCTAssertEqual(errors.count, 1, "The load completion handler must fire exactly once")
        XCTAssertEqual(errors.first!?.domain, VelocityAdsErrorMapper.sdkDomain)
        XCTAssertEqual(errors.first!?.code, RequestError.Code.noFill.rawValue)
        XCTAssertEqual(finished, 2, "Every terminal callback releases the creative (destroy is idempotent)")
    }

    func test_displayEvents_translateInOrder() {
        let ad = makeAd()
        let velocityAd = makeInterstitial()
        ad.delegate?.onAdLoaded(ad: velocityAd)

        ad.delegate?.onAdShown(ad: velocityAd)
        ad.delegate?.onAdImpression(ad: velocityAd)
        ad.delegate?.onAdClicked(ad: velocityAd)
        ad.delegate?.onAdDismissed(ad: velocityAd)

        XCTAssertEqual(spy.events, ["willPresent", "impression", "click", "willDismiss", "didDismiss"])
        XCTAssertEqual(finished, 1, "Dismissal releases the single-use creative")
    }

    func test_onAdFailedToShow_forwardsMappedError() {
        let ad = makeAd()
        let velocityAd = makeInterstitial()
        ad.delegate?.onAdLoaded(ad: velocityAd)

        ad.delegate?.onAdFailedToShow(ad: velocityAd, error: sdkError)

        XCTAssertEqual(spy.events, ["failToPresent"])
        XCTAssertEqual(spy.presentError?.domain, VelocityAdsErrorMapper.sdkDomain)
    }

    func test_displayEventsBeforeLoad_areDropped() {
        let ad = makeAd()
        ad.delegate?.onAdShown(ad: makeInterstitial())
        ad.delegate?.onAdClicked(ad: makeInterstitial())

        XCTAssertTrue(spy.events.isEmpty)
    }

    func test_present_withoutALoadedCreative_reportsAdNotReady() {
        let ad = makeAd()
        ad.delegate?.onAdLoaded(ad: makeInterstitial())

        ad.present(from: UIViewController())

        XCTAssertEqual(spy.events, ["failToPresent"])
        XCTAssertEqual(spy.presentError?.domain, VelocityAdsErrorMapper.adapterDomain)
        XCTAssertEqual(spy.presentError?.code, VelocityAdsErrorMapper.AdapterErrorCode.adNotReady.rawValue)
    }

    func test_onAdLoaded_afterTheOwnerWasReleased_reportsAdapterReleased() {
        var delegate: VelocityInterstitialAdapterDelegate?
        autoreleasepool {
            let ad = makeAd()
            delegate = ad.delegate
        }
        delegate?.onAdLoaded(ad: makeInterstitial())

        XCTAssertEqual(completions.count, 1)
        XCTAssertNil(completions.first!)
        XCTAssertEqual(errors.first!?.code, VelocityAdsErrorMapper.AdapterErrorCode.adapterReleased.rawValue)
    }
}

// MARK: - Rewarded

@MainActor
final class VelocityRewardedAdapterDelegateTests: XCTestCase {

    private var completions: [(any MediationRewardedAd)?] = []
    private var errors: [NSError?] = []
    private var finished = 0
    private var spy = RewardedEventSpy()

    private func makeAd() -> VelocityGmaRewardedAd {
        spy = RewardedEventSpy()
        let ad = VelocityGmaRewardedAd(ad: makeRewarded()) { [weak self] mediationAd, error in
            self?.completions.append(mediationAd)
            self?.errors.append(error as NSError?)
            return self?.spy
        }
        ad.onAdFinished = { [weak self] in self?.finished += 1 }
        return ad
    }

    func test_onAdLoaded_handsTheAdToGoogleAndCapturesTheEventDelegate() {
        let ad = makeAd()
        ad.delegate?.onAdLoaded(ad: makeRewarded())

        XCTAssertEqual(completions.count, 1)
        XCTAssertTrue(completions.first! === ad)
        XCTAssertTrue(ad.delegate?.eventDelegate === spy)
    }

    func test_onAdFailedToLoad_reportsMappedErrorOnce() {
        let ad = makeAd()
        ad.delegate?.onAdFailedToLoad(ad: makeRewarded(), error: sdkError)
        ad.delegate?.onAdFailedToLoad(ad: makeRewarded(), error: sdkError)

        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first!?.code, RequestError.Code.noFill.rawValue)
    }

    func test_rewardIsDeliveredBeforeDismissal_andNoVideoSignalsAreEmitted() {
        let ad = makeAd()
        let velocityAd = makeRewarded()
        ad.delegate?.onAdLoaded(ad: velocityAd)

        ad.delegate?.onAdShown(ad: velocityAd)
        ad.delegate?.onAdImpression(ad: velocityAd)
        ad.delegate?.onUserRewarded(ad: velocityAd)
        ad.delegate?.onAdDismissed(ad: velocityAd)

        XCTAssertEqual(spy.events, ["willPresent", "impression", "reward", "willDismiss", "didDismiss"])
        XCTAssertEqual(finished, 1)
    }

    func test_present_withoutALoadedCreative_reportsAdNotReady() {
        let ad = makeAd()
        ad.delegate?.onAdLoaded(ad: makeRewarded())

        ad.present(from: UIViewController())

        XCTAssertEqual(spy.events, ["failToPresent"])
        XCTAssertEqual(spy.presentError?.code, VelocityAdsErrorMapper.AdapterErrorCode.adNotReady.rawValue)
    }

    func test_onAdLoaded_afterTheOwnerWasReleased_reportsAdapterReleased() {
        var delegate: VelocityRewardedAdapterDelegate?
        autoreleasepool {
            let ad = makeAd()
            delegate = ad.delegate
        }
        delegate?.onAdLoaded(ad: makeRewarded())

        XCTAssertNil(completions.first!)
        XCTAssertEqual(errors.first!?.code, VelocityAdsErrorMapper.AdapterErrorCode.adapterReleased.rawValue)
    }
}

// MARK: - Banner

@MainActor
final class VelocityBannerAdapterDelegateTests: XCTestCase {

    private var completions: [(any MediationBannerAd)?] = []
    private var errors: [NSError?] = []
    private var spy = BannerEventSpy()

    private func makeAd() -> (VelocityGmaBannerAd, VelocityBannerAd) {
        spy = BannerEventSpy()
        let (velocityAd, adView) = makeBanner()
        let ad = VelocityGmaBannerAd(ad: velocityAd, adView: adView) { [weak self] mediationAd, error in
            self?.completions.append(mediationAd)
            self?.errors.append(error as NSError?)
            return self?.spy
        }
        return (ad, velocityAd)
    }

    func test_view_isTheHostingVelocityBannerView() {
        let (ad, _) = makeAd()
        XCTAssertTrue(ad.view is VelocityBannerAdView)
        XCTAssertEqual(ad.view.frame.size, CGSize(width: 320, height: 50))
    }

    func test_onAdLoaded_handsTheAdToGoogleAndCapturesTheEventDelegate() {
        let (ad, velocityAd) = makeAd()
        ad.delegate?.onAdLoaded(ad: velocityAd)

        XCTAssertTrue(completions.first! === ad)
        XCTAssertTrue(ad.delegate?.eventDelegate === spy)
    }

    func test_onAdFailedToLoad_reportsMappedErrorOnce() {
        let (ad, velocityAd) = makeAd()
        ad.delegate?.onAdFailedToLoad(ad: velocityAd, error: sdkError)
        ad.delegate?.onAdFailedToLoad(ad: velocityAd, error: sdkError)

        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first!?.code, RequestError.Code.noFill.rawValue)
    }

    func test_impressionAndClick_areForwarded_andRenderFailureIsOnlyLogged() {
        let (ad, velocityAd) = makeAd()
        ad.delegate?.onAdLoaded(ad: velocityAd)

        ad.delegate?.onAdImpression(ad: velocityAd)
        ad.delegate?.onAdClicked(ad: velocityAd)
        ad.delegate?.onAdFailedToShow(ad: velocityAd, error: sdkError)

        XCTAssertEqual(spy.events, ["impression", "click"])
    }

    func test_onAdLoaded_afterTheOwnerWasReleased_reportsAdapterReleased() {
        var delegate: VelocityBannerAdapterDelegate?
        var velocityAd: VelocityBannerAd?
        autoreleasepool {
            let (ad, banner) = makeAd()
            delegate = ad.delegate
            velocityAd = banner
        }
        delegate?.onAdLoaded(ad: velocityAd!)

        XCTAssertNil(completions.first!)
        XCTAssertEqual(errors.first!?.code, VelocityAdsErrorMapper.AdapterErrorCode.adapterReleased.rawValue)
    }
}
