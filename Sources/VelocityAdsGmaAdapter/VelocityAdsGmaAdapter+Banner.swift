import GoogleMobileAds
import UIKit
import VelocityAdsSDK

// MARK: - Banner load

extension VelocityAdsGmaAdapter {

    @MainActor
    func loadBannerOnMain(
        for adConfiguration: MediationBannerAdConfiguration,
        completionHandler: @escaping GADMediationBannerLoadCompletionHandler
    ) {
        let parameters = VelocityAdsServerParameters.parse(credentials: adConfiguration.credentials)
        guard let adUnitId = parameters.adUnitId else {
            _ = completionHandler(nil, VelocityAdsErrorMapper.invalidServerParameters())
            return
        }
        guard let size = VelocityAdsGmaAdapter.resolveBannerSize(adConfiguration.adSize) else {
            _ = completionHandler(nil, VelocityAdsErrorMapper.invalidAdSize(string(for: adConfiguration.adSize)))
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

            let request = VelocityBannerAdRequest.Builder(adUnitId: adUnitId, adSize: size).build()
            // GADBannerView adds the mediated view as-is and does not size it; a zero frame
            // renders nothing. Size it to the requested ad size up front, as Google's own
            // sample custom event does.
            let adView = VelocityBannerAdView(frame: CGRect(origin: .zero, size: cgSize(for: adConfiguration.adSize)))
            let mediationAd = VelocityGmaBannerAd(
                ad: VelocityBannerAd(request),
                adView: adView,
                completionHandler: completionHandler
            )
            self.bannerAd = mediationAd
            mediationAd.load()
        }
    }

    // MARK: - Banner size resolution

    /// Resolves the Velocity banner size for a Google Mobile Ads request.
    ///
    /// - The standard IAB dimensions map to their Velocity presets so the server can apply
    ///   size-class-specific fill rules.
    /// - Every other valid size — anchored adaptive, inline adaptive, full-width — arrives
    ///   from the Google Mobile Ads SDK as concrete points and is forwarded verbatim as a
    ///   custom size.
    /// - `AdSizeFluid` and `AdSizeInvalid` have no fixed dimensions and cannot be served —
    ///   returns `nil`.
    ///
    /// Pure (no UIKit / global state access) so it can be unit-tested in isolation.
    static func resolveBannerSize(_ adSize: AdSize) -> VelocityBannerAdSize? {
        guard isAdSizeValid(size: adSize), !isAdSizeFluid(size: adSize) else {
            return nil
        }
        let size = cgSize(for: adSize)
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        if size == cgSize(for: AdSizeBanner) {
            return .banner
        }
        if size == cgSize(for: AdSizeMediumRectangle) {
            return .mrec
        }
        if size == cgSize(for: AdSizeLeaderboard) {
            return .leaderboard
        }
        return .custom(width: size.width, height: size.height)
    }
}

// MARK: - VelocityGmaBannerAd

/// Handles the `MediationBannerAd` contract for `VelocityAdsGmaAdapter`.
///
/// Owns the `VelocityBannerAd`, the `VelocityBannerAdView` that hosts the creative and the
/// `VelocityBannerAdapterDelegate` for one load cycle. Main-actor-confined: both SDKs
/// deliver every callback on the main thread.
@MainActor
final class VelocityGmaBannerAd: NSObject, MediationBannerAd {

    private let ad: VelocityBannerAd
    private let adView: VelocityBannerAdView
    private(set) var delegate: VelocityBannerAdapterDelegate?

    init(ad: VelocityBannerAd, adView: VelocityBannerAdView, completionHandler: @escaping GADMediationBannerLoadCompletionHandler) {
        self.ad = ad
        self.adView = adView
        super.init()
        let delegate = VelocityBannerAdapterDelegate(mediationAd: self, completionHandler: completionHandler)
        delegate.onLoadFailed = { [weak self] in
            self?.ad.destroy()
        }
        self.delegate = delegate
    }

    func load() {
        guard let delegate else { return }
        ad.load(bannerView: adView, delegate: delegate)
    }

    // MARK: MediationBannerAd

    /// Google's protocol is not actor-annotated, so the requirement is satisfied as
    /// `nonisolated` and re-enters the main actor explicitly; the Google Mobile Ads SDK
    /// reads the view on the main thread when it attaches the banner.
    nonisolated var view: UIView {
        MainActor.assumeIsolated { adView }
    }
}
