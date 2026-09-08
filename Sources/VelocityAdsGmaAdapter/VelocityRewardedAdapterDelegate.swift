import GoogleMobileAds
import VelocityAdsSDK

/// Bridges `VelocityRewardedAdDelegate` callbacks to the Google Mobile Ads SDK.
///
/// Load-phase events go to the load completion handler; once the SDK accepts the ad the
/// returned `MediationRewardedAdEventDelegate` receives every display-phase event.
///
/// Reward amount and type are configured in the AdMob UI; `didRewardUser()` lets the
/// Google Mobile Ads SDK fill in the ad unit's configured values. Video start/end signals
/// are intentionally not emitted: Velocity creatives are not necessarily video.
///
/// The Velocity SDK delivers all callbacks on the main thread (the protocol is
/// `@MainActor`), so no additional dispatching is required before forwarding.
@MainActor
final class VelocityRewardedAdapterDelegate: NSObject, VelocityRewardedAdDelegate {

    // MARK: - Properties

    /// The ad object handed to the Google Mobile Ads SDK on success. Weak: the ad object
    /// owns this delegate.
    private weak var mediationAd: (any MediationRewardedAd)?
    private var completionHandler: GADMediationRewardedLoadCompletionHandler?

    /// Set once the Google Mobile Ads SDK accepts the loaded ad via the completion handler.
    private(set) var eventDelegate: MediationRewardedAdEventDelegate?

    /// Called once the creative is no longer usable (load failed or the ad was dismissed)
    /// so the owner can release it.
    var onAdFinished: (@MainActor () -> Void)?

    init(
        mediationAd: any MediationRewardedAd,
        completionHandler: @escaping GADMediationRewardedLoadCompletionHandler
    ) {
        self.mediationAd = mediationAd
        self.completionHandler = completionHandler
    }

    // MARK: - VelocityRewardedAdDelegate / VelocityFullscreenAdDelegate

    func onAdLoaded(ad: any VelocityFullscreenAd) {
        guard let mediationAd else {
            _ = completionHandler?(nil, VelocityAdsErrorMapper.adapterReleased())
            completionHandler = nil
            return
        }
        eventDelegate = completionHandler?(mediationAd, nil)
        completionHandler = nil
    }

    func onAdFailedToLoad(ad: any VelocityFullscreenAd, error: VelocityAdsError) {
        _ = completionHandler?(nil, VelocityAdsErrorMapper.map(error))
        completionHandler = nil
        onAdFinished?()
    }

    func onAdShown(ad: any VelocityFullscreenAd) {
        eventDelegate?.willPresentFullScreenView()
    }

    func onAdImpression(ad: any VelocityFullscreenAd) {
        eventDelegate?.reportImpression()
    }

    func onAdFailedToShow(ad: any VelocityFullscreenAd, error: VelocityAdsError) {
        eventDelegate?.didFailToPresentWithError(VelocityAdsErrorMapper.map(error))
    }

    func onAdClicked(ad: any VelocityFullscreenAd) {
        eventDelegate?.reportClick()
    }

    /// Fires before `onAdDismissed` per the Velocity callback contract.
    func onUserRewarded(ad: any VelocityFullscreenAd) {
        eventDelegate?.didRewardUser()
    }

    func onAdDismissed(ad: any VelocityFullscreenAd) {
        eventDelegate?.willDismissFullScreenView()
        eventDelegate?.didDismissFullScreenView()
        onAdFinished?()
    }
}
