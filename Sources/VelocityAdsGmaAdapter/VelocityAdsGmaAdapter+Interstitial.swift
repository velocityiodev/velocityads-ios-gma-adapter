import GoogleMobileAds
import UIKit
import VelocityAdsSDK

// MARK: - Interstitial load

extension VelocityAdsGmaAdapter {

    @MainActor
    func loadInterstitialOnMain(
        for adConfiguration: MediationInterstitialAdConfiguration,
        completionHandler: @escaping GADMediationInterstitialLoadCompletionHandler
    ) {
        let parameters = VelocityAdsServerParameters.parse(credentials: adConfiguration.credentials)
        guard let adUnitId = parameters.adUnitId else {
            _ = completionHandler(nil, VelocityAdsErrorMapper.invalidServerParameters())
            return
        }

        VelocityAdsGmaAdapter.ensureInitialized(with: parameters) { [weak self] initialized in
            guard let self else {
                _ = completionHandler(nil, VelocityAdsErrorMapper.adapterReleased())
                return
            }
            guard initialized else {
                _ = completionHandler(nil, VelocityAdsErrorMapper.sdkNotInitialized())
                return
            }

            let request = VelocityInterstitialAdRequest.Builder(adUnitId: adUnitId).build()
            let mediationAd = VelocityGmaInterstitialAd(ad: VelocityInterstitialAd(request), completionHandler: completionHandler)
            mediationAd.onAdFinished = { [weak self] in
                self?.interstitialAd = nil
            }
            self.interstitialAd = mediationAd
            mediationAd.load()
        }
    }
}

// MARK: - VelocityGmaInterstitialAd

/// Handles the `MediationInterstitialAd` contract for `VelocityAdsGmaAdapter`.
///
/// Owns the `VelocityInterstitialAd` and its `VelocityInterstitialAdapterDelegate` for one
/// load cycle. A fullscreen ad is single-use: the creative is released as soon as the load
/// fails or the ad is dismissed. Main-actor-confined: both SDKs deliver every callback on
/// the main thread.
@MainActor
final class VelocityGmaInterstitialAd: NSObject, @preconcurrency MediationInterstitialAd {

    private let ad: VelocityInterstitialAd
    private var delegate: VelocityInterstitialAdapterDelegate?

    /// Called once the creative has been released so the owning adapter can drop its reference.
    var onAdFinished: (@MainActor () -> Void)?

    init(ad: VelocityInterstitialAd, completionHandler: @escaping GADMediationInterstitialLoadCompletionHandler) {
        self.ad = ad
        super.init()
        let delegate = VelocityInterstitialAdapterDelegate(mediationAd: self, completionHandler: completionHandler)
        delegate.onAdFinished = { [weak self] in
            self?.ad.destroy()
            self?.onAdFinished?()
        }
        self.delegate = delegate
    }

    func load() {
        guard let delegate else { return }
        ad.load(delegate: delegate)
    }

    // MARK: MediationInterstitialAd

    /// The view controller is deliberately not forwarded: the Velocity SDK's own
    /// topmost-view-controller resolution handles presentation.
    func present(from viewController: UIViewController) {
        guard ad.isReady else {
            delegate?.eventDelegate?.didFailToPresentWithError(VelocityAdsErrorMapper.adNotReady())
            return
        }
        ad.show()
    }
}
