import GoogleMobileAds
import VelocityAdsSDK

/// Bridges `VelocityInterstitialAdDelegate` callbacks to the Google Mobile Ads SDK.
///
/// Load-phase events go to the load completion handler; once the SDK accepts the ad the
/// returned `MediationInterstitialAdEventDelegate` receives every display-phase event.
///
/// The Velocity SDK delivers all callbacks on the main thread (the protocol is
/// `@MainActor`), so no additional dispatching is required before forwarding.
@MainActor
final class VelocityInterstitialAdapterDelegate: NSObject, VelocityInterstitialAdDelegate {

    // MARK: - Properties

    /// The ad object handed to the Google Mobile Ads SDK on success. Weak: the ad object
    /// owns this delegate.
    private weak var mediationAd: (any MediationInterstitialAd)?
    private var completionHandler: GADMediationInterstitialLoadCompletionHandler?

    /// Set once the Google Mobile Ads SDK accepts the loaded ad via the completion handler.
    private(set) var eventDelegate: MediationInterstitialAdEventDelegate?

    /// Called once the creative is no longer usable (load failed or the ad was dismissed)
    /// so the owner can release it.
    var onAdFinished: (@MainActor () -> Void)?

    init(
        mediationAd: any MediationInterstitialAd,
        completionHandler: @escaping GADMediationInterstitialLoadCompletionHandler
    ) {
        self.mediationAd = mediationAd
        self.completionHandler = completionHandler
    }

    // MARK: - VelocityInterstitialAdDelegate / VelocityFullscreenAdDelegate

    func onAdLoaded(ad: any VelocityFullscreenAd) {
        guard let mediationAd else {
            _ = completionHandler?(nil, VelocityAdsErrorMapper.adNotReady())
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

    func onAdDismissed(ad: any VelocityFullscreenAd) {
        eventDelegate?.willDismissFullScreenView()
        eventDelegate?.didDismissFullScreenView()
        onAdFinished?()
    }
}
