import Foundation
import GoogleMobileAds
import VelocityAdsSDK

// MARK: - VelocityAdsGmaAdapter

/// Google Mobile Ads (AdMob / Google Ad Manager) custom event adapter for the Velocity Ads iOS SDK.
///
/// Register this class in the AdMob UI under **Mediation → Custom events** with the iOS
/// class name `VelocityAdsGmaAdapter`. The **Parameter** field carries the Velocity
/// configuration for the mapping — see `VelocityAdsServerParameters` for the accepted format.
///
/// Supported ad formats: Interstitial, Rewarded, Banner / MREC / Leaderboard / Adaptive banner.
///
/// The Google Mobile Ads SDK creates one adapter instance per ad request and calls the load
/// entry points on the main thread; `setUp(with:completionHandler:)` and the version getters
/// are class-level and may be called from a background queue.
@objc(VelocityAdsGmaAdapter)
public final class VelocityAdsGmaAdapter: NSObject, MediationAdapter {

    // MARK: - State — loaded ads

    /// The in-flight or loaded ad for this adapter instance. Retained here because the
    /// Velocity SDK holds its delegate weakly; once the Google Mobile Ads SDK accepts the
    /// ad it also retains the same object via the load completion handler.
    var interstitialAd: VelocityGmaInterstitialAd?
    var rewardedAd: VelocityGmaRewardedAd?
    var bannerAd: VelocityGmaBannerAd?

    // MARK: - MediationAdapter — class level

    public override required init() {
        super.init()
    }

    public static func adapterVersion() -> VersionNumber {
        VersionNumberParser.adapterVersion(velocityAdsGmaAdapterVersion)
    }

    public static func adSDKVersion() -> VersionNumber {
        VersionNumberParser.sdkVersion(VelocityAds.getSdkVersion())
    }

    public static func networkExtrasClass() -> (any AdNetworkExtras.Type)? {
        nil
    }

    public static func setUp(
        with configuration: MediationServerConfiguration,
        completionHandler: @escaping GADMediationAdapterSetUpCompletionBlock
    ) {
        forwardMediationInfo()

        if VelocityAds.isInitialized() {
            completionHandler(nil)
            return
        }

        // No mapping carries an appKey: either the host app initializes the Velocity SDK
        // itself, or the key arrives at load time. Report success so the Google Mobile Ads
        // SDK's own initialization is never blocked; ensureInitialized() performs the real
        // SDK init lazily on the first load.
        guard let configuredAppKey = firstAppKey(in: configuration) else {
            completionHandler(nil)
            return
        }

        // Adapters are set up on a background queue; the coalescer and the Velocity init
        // delegate are main-actor-confined.
        runOnMainNow {
            let appKey = rememberAppKey(configuredAppKey)
            if VelocityAds.isInitialized() {
                completionHandler(nil)
                return
            }
            let won = initCoalescer.claim { outcome in
                completionHandler(outcome)
            }
            if won {
                startClaimedInit(appKey: appKey)
            }
        }
    }

    // MARK: - MediationAdapter — load entry points

    public func loadInterstitial(
        for adConfiguration: MediationInterstitialAdConfiguration,
        completionHandler: @escaping GADMediationInterstitialLoadCompletionHandler
    ) {
        VelocityAdsGmaAdapter.forwardMediationInfo()
        VelocityAdsGmaAdapter.runOnMainNow { [weak self] in
            guard let self else {
                _ = completionHandler(nil, VelocityAdsErrorMapper.adapterReleased())
                return
            }
            self.loadInterstitialOnMain(for: adConfiguration, completionHandler: completionHandler)
        }
    }

    public func loadRewardedAd(
        for adConfiguration: MediationRewardedAdConfiguration,
        completionHandler: @escaping GADMediationRewardedLoadCompletionHandler
    ) {
        VelocityAdsGmaAdapter.forwardMediationInfo()
        VelocityAdsGmaAdapter.runOnMainNow { [weak self] in
            guard let self else {
                _ = completionHandler(nil, VelocityAdsErrorMapper.adapterReleased())
                return
            }
            self.loadRewardedOnMain(for: adConfiguration, completionHandler: completionHandler)
        }
    }

    public func loadBanner(
        for adConfiguration: MediationBannerAdConfiguration,
        completionHandler: @escaping GADMediationBannerLoadCompletionHandler
    ) {
        VelocityAdsGmaAdapter.forwardMediationInfo()
        VelocityAdsGmaAdapter.runOnMainNow { [weak self] in
            guard let self else {
                _ = completionHandler(nil, VelocityAdsErrorMapper.adapterReleased())
                return
            }
            self.loadBannerOnMain(for: adConfiguration, completionHandler: completionHandler)
        }
    }

    // MARK: - Main-thread helper

    /// Executes `block` on the main actor — inline when already on the main
    /// thread, otherwise deferred via `DispatchQueue.main.async`.
    ///
    /// The Google Mobile Ads SDK documents that load entry points are invoked on the
    /// main thread, so the inline path is the norm there; `setUp` runs on a background
    /// queue and always takes the async path.
    static func runOnMainNow(_ block: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(block)
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated(block)
            }
        }
    }
}
