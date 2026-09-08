import Foundation
import GoogleMobileAds
import VelocityAdsSDK

// MARK: - Init coalescing, app-key memory and mediation info

extension VelocityAdsGmaAdapter {

    /// `nil` on success, otherwise the error to report to the Google Mobile Ads SDK.
    typealias InitOutcome = NSError?

    /// Coalesces concurrent `VelocityAds.initSDK` attempts across adapter instances:
    /// only the first caller performs the SDK call; everyone else parks a handler
    /// and receives the winner's broadcast. This prevents the SDK from rejecting
    /// the second call with SDK_INITIALIZATION_IN_PROGRESS and the Google Mobile Ads
    /// SDK from treating that rejection as a permanent failure.
    @MainActor
    static let initCoalescer = InitCoalescer<InitOutcome>()

    /// The init bridge for the currently claimed SDK init attempt.
    ///
    /// Coalescer-scoped (static) rather than instance-scoped on purpose: the SDK
    /// makes no documented promise about init-delegate retention, and this bridge's
    /// `onSuccess` / `onFailure` callbacks are the only paths that complete the
    /// shared coalescer. The bridge clears this slot itself when its terminal
    /// callback fires.
    @MainActor
    private static var activeInitBridge: VelocityAdsInitBridge?

    /// The app key captured from the first sighting, used as a fallback for load-time
    /// init attempts whose parameter carries only an ad unit ID. First-wins: Velocity
    /// init is process-global, so later mismatched keys are logged and ignored.
    @MainActor
    private(set) static var storedAppKey: String?

    @MainActor
    private static var appKeyMismatchLogged = false

    #if DEBUG
    /// Test-only: replaces the `VelocityAds.initSDK` trigger so unit tests can
    /// drive the coalesced init flow deterministically without network I/O.
    @MainActor
    static var initSDKRunnerForTesting: ((VelocityAdsInitRequest, VelocityAdsInitDelegate) -> Void)?

    /// Test-only: drains and unclaims the shared coalescer and clears all test
    /// seams and remembered state so nothing leaks between test cases.
    @MainActor
    static func resetInitStateForTesting() {
        if initCoalescer.isClaimed {
            initCoalescer.complete(with: NSError(domain: VelocityAdsErrorMapper.adapterDomain, code: -1))
        }
        activeInitBridge = nil
        storedAppKey = nil
        appKeyMismatchLogged = false
        initSDKRunnerForTesting = nil
    }
    #endif

    // MARK: - Server parameter helpers

    /// Finds the first non-blank `appKey` across the credentials the Google Mobile Ads SDK
    /// hands to `setUp` — one per custom event mapping in the account.
    static func firstAppKey(in configuration: MediationServerConfiguration) -> String? {
        for credentials in configuration.credentials {
            if let appKey = VelocityAdsServerParameters.parse(credentials: credentials).appKey {
                return appKey
            }
        }
        return nil
    }

    @MainActor
    static func rememberAppKey(_ appKey: String) {
        guard let previous = storedAppKey else {
            storedAppKey = appKey
            return
        }
        if previous != appKey, !appKeyMismatchLogged {
            appKeyMismatchLogged = true
            AdapterLog.warn(
                "Velocity Ads: multiple appKey values detected across custom event parameters. "
                    + "Use one Velocity app key per application process."
            )
        }
    }

    // MARK: - Init helpers

    /// Ensures the Velocity SDK is initialized before a load proceeds.
    ///
    /// If the SDK is already up, `completion(true)` fires synchronously. Otherwise an init
    /// is attempted (or coalesced onto an in-flight attempt) with the `appKey` from the
    /// load-time parameters, falling back to the key remembered from `setUp`. This covers
    /// both the lazy-init contract (no key at startup) and transient failures of the
    /// startup init (e.g. no connectivity at launch) — the Velocity SDK explicitly permits
    /// re-init from its FAILED state.
    @MainActor
    static func ensureInitialized(
        with parameters: VelocityAdsServerParameters,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if VelocityAds.isInitialized() {
            completion(true)
            return
        }

        if let loadAppKey = parameters.appKey {
            rememberAppKey(loadAppKey)
        }
        guard let appKey = parameters.appKey ?? storedAppKey else {
            completion(false)
            return
        }

        let won = initCoalescer.claim { outcome in
            completion(outcome == nil)
        }
        if won {
            startClaimedInit(appKey: appKey)
        }
    }

    /// Performs the actual `VelocityAds.initSDK` call on behalf of the caller
    /// that won the coalescer claim, broadcasting the outcome to every parked
    /// handler when the SDK responds.
    @MainActor
    static func startClaimedInit(appKey: String) {
        let request = VelocityAdsInitRequest.Builder(appKey).build()
        let bridge = VelocityAdsInitBridge(
            onSuccess: {
                activeInitBridge = nil
                initCoalescer.complete(with: nil)
            },
            onFailure: { error in
                activeInitBridge = nil
                if error.code == VelocityAdsErrorCode.sdkInitializationInProgress {
                    // The host app called VelocityAds.initSDK moments before the adapter
                    // did, so the SDK rejected our call. Not a permanent failure — wait
                    // for the in-flight init and report the real outcome. The claim stays
                    // held during polling so concurrent callers keep parking on the
                    // coalescer; the poller is the single remaining completer.
                    InFlightInitPoller.awaitInitialization(
                        isInitialized: { VelocityAds.isInitialized() }
                    ) { initialized in
                        let outcome: InitOutcome = initialized
                            ? nil
                            : NSError(
                                domain: VelocityAdsErrorMapper.adapterDomain,
                                code: VelocityAdsErrorMapper.AdapterErrorCode.sdkNotInitialized.rawValue,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "Velocity Ads: timed out waiting for in-flight SDK initialization"]
                            )
                        initCoalescer.complete(with: outcome)
                    }
                    return
                }
                initCoalescer.complete(with: VelocityAdsErrorMapper.map(error))
            }
        )
        activeInitBridge = bridge
        #if DEBUG
        if let runner = initSDKRunnerForTesting {
            runner(request, bridge)
            return
        }
        #endif
        VelocityAds.initSDK(request, delegate: bridge)
    }

    // MARK: - Mediation info

    /// One-shot forwarding of the mediation environment to the Velocity SDK. The `static let`
    /// closure gives thread-safe once semantics for free.
    private static let mediationInfoForwardingToken: Void = {
        VelocityAdsMediationBridge.setMediationInfo(
            name: velocityAdsMediationName,
            adapterVersion: velocityAdsGmaAdapterVersion,
            sdkVersion: string(for: MobileAds.shared.versionNumber)
        )
    }()

    /// Reports the mediation environment to the Velocity SDK. Idempotent; safe from any entry point.
    static func forwardMediationInfo() {
        _ = mediationInfoForwardingToken
    }
}

// MARK: - VelocityAdsInitBridge

/// Internal helper that routes `VelocityAdsInitDelegate` callbacks to the
/// adapter's init-completion logic. Kept alive in the coalescer-scoped
/// `activeInitBridge` slot. Failures are forwarded with the raw `VelocityAdsError`
/// so the caller can distinguish transient states (e.g. SDK_INITIALIZATION_IN_PROGRESS)
/// from permanent failures.
///
/// Marked `@MainActor` because `VelocityAdsInitDelegate` is a `@MainActor` protocol.
@MainActor
private final class VelocityAdsInitBridge: NSObject, VelocityAdsInitDelegate {

    private let onSuccess: () -> Void
    private let onFailure: (VelocityAdsError) -> Void

    init(onSuccess: @escaping () -> Void, onFailure: @escaping (VelocityAdsError) -> Void) {
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    func onInitSuccess() {
        onSuccess()
    }

    func onInitFailure(error: VelocityAdsError) {
        onFailure(error)
    }
}
