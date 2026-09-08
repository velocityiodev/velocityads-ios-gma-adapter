import GoogleMobileAds
import UIKit
import VelocityAdsSDK

// MARK: - Rewarded load

extension VelocityAdsGmaAdapter {

    @MainActor
    func loadRewardedOnMain(
        for adConfiguration: MediationRewardedAdConfiguration,
        completionHandler: @escaping GADMediationRewardedLoadCompletionHandler
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

            let request = VelocityRewardedAdRequest.Builder(adUnitId: adUnitId).build()
            let mediationAd = VelocityGmaRewardedAd(ad: VelocityRewardedAd(request), completionHandler: completionHandler)
            mediationAd.onAdFinished = { [weak self] in
                self?.rewardedAd = nil
            }
            self.rewardedAd = mediationAd
            mediationAd.load()
        }
    }
}

// MARK: - VelocityGmaRewardedAd

/// Handles the `MediationRewardedAd` contract for `VelocityAdsGmaAdapter`.
///
/// Owns the `VelocityRewardedAd` and its `VelocityRewardedAdapterDelegate` for one load
/// cycle. A fullscreen ad is single-use: the creative is released as soon as the load fails
/// or the ad is dismissed. Main-actor-confined: both SDKs deliver every callback on the
/// main thread.
@MainActor
final class VelocityGmaRewardedAd: NSObject, @preconcurrency MediationRewardedAd {

    private let ad: VelocityRewardedAd
    private(set) var delegate: VelocityRewardedAdapterDelegate?

    /// Called once the creative has been released so the owning adapter can drop its reference.
    var onAdFinished: (@MainActor () -> Void)?

    init(ad: VelocityRewardedAd, completionHandler: @escaping GADMediationRewardedLoadCompletionHandler) {
        self.ad = ad
        super.init()
        let delegate = VelocityRewardedAdapterDelegate(mediationAd: self, completionHandler: completionHandler)
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

    // MARK: MediationRewardedAd

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
