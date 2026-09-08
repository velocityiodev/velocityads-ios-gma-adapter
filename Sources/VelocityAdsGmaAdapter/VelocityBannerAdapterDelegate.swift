import GoogleMobileAds
import VelocityAdsSDK

/// Bridges `VelocityBannerAdDelegate` callbacks to the Google Mobile Ads SDK.
///
/// Load-phase events go to the load completion handler; once the SDK accepts the ad the
/// returned `MediationBannerAdEventDelegate` receives impression and click events.
///
/// The Velocity SDK delivers all callbacks on the main thread (the protocol is
/// `@MainActor`), so no additional dispatching is required before forwarding.
@MainActor
final class VelocityBannerAdapterDelegate: NSObject, VelocityBannerAdDelegate {

    // MARK: - Properties

    /// The ad object handed to the Google Mobile Ads SDK on success. Weak: the ad object
    /// owns this delegate.
    private weak var mediationAd: (any MediationBannerAd)?
    private var completionHandler: GADMediationBannerLoadCompletionHandler?

    /// Set once the Google Mobile Ads SDK accepts the loaded ad via the completion handler.
    private(set) var eventDelegate: MediationBannerAdEventDelegate?

    /// Called after a load failure so the owner can release the creative.
    var onLoadFailed: (@MainActor () -> Void)?

    init(
        mediationAd: any MediationBannerAd,
        completionHandler: @escaping GADMediationBannerLoadCompletionHandler
    ) {
        self.mediationAd = mediationAd
        self.completionHandler = completionHandler
    }

    // MARK: - VelocityBannerAdDelegate

    func onAdLoaded(ad: VelocityBannerAd) {
        guard let mediationAd else {
            _ = completionHandler?(nil, VelocityAdsErrorMapper.adapterReleased())
            completionHandler = nil
            return
        }
        eventDelegate = completionHandler?(mediationAd, nil)
        completionHandler = nil
    }

    func onAdFailedToLoad(ad: VelocityBannerAd, error: VelocityAdsError) {
        _ = completionHandler?(nil, VelocityAdsErrorMapper.map(error))
        completionHandler = nil
        onLoadFailed?()
    }

    /// Emitted on Velocity's viewability-gated impression rather than on load, so the
    /// impression the Google Mobile Ads SDK records matches Velocity's own accounting.
    func onAdImpression(ad: VelocityBannerAd) {
        eventDelegate?.reportImpression()
    }

    func onAdClicked(ad: VelocityBannerAd) {
        eventDelegate?.reportClick()
    }

    func onAdFailedToShow(ad: VelocityBannerAd, error: VelocityAdsError) {
        // The Google Mobile Ads banner contract has no post-load failure hook — the SDK already
        // holds the view — so the failure is only logged for diagnosis of a blank slot.
        AdapterLog.warn("Velocity Ads banner failed to render [\(error.code)]: \(error.message)")
    }
}
