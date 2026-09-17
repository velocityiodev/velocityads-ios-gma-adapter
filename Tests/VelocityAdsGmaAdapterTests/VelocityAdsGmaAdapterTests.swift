import GoogleMobileAds
import UIKit
import VelocityAdsSDK
import XCTest

@testable import VelocityAdsGmaAdapter

// MARK: - Stub configurations

/// The Google Mobile Ads configuration classes expose read-only properties and no public
/// initializers, so the tests subclass them and override the getters the adapter reads.

private final class StubCredentials: MediationCredentials {
    private let parameter: String?

    init(parameter: String?) {
        self.parameter = parameter
        super.init()
    }

    override var settings: [String: Any] {
        guard let parameter else { return [:] }
        return [GADCustomEventParametersServer: parameter]
    }
}

private final class StubServerConfiguration: MediationServerConfiguration {
    private let stubCredentials: [MediationCredentials]

    init(parameters: [String?]) {
        stubCredentials = parameters.map { StubCredentials(parameter: $0) }
        super.init()
    }

    override var credentials: [MediationCredentials] { stubCredentials }
}

private final class StubInterstitialConfiguration: MediationInterstitialAdConfiguration {
    private let parameter: String?

    init(parameter: String?) {
        self.parameter = parameter
        super.init()
    }

    override var credentials: MediationCredentials { StubCredentials(parameter: parameter) }
}

private final class StubRewardedConfiguration: MediationRewardedAdConfiguration {
    private let parameter: String?

    init(parameter: String?) {
        self.parameter = parameter
        super.init()
    }

    override var credentials: MediationCredentials { StubCredentials(parameter: parameter) }
}

private final class StubBannerConfiguration: MediationBannerAdConfiguration {
    private let parameter: String?
    private let size: AdSize

    init(parameter: String?, adSize: AdSize = AdSizeBanner) {
        self.parameter = parameter
        self.size = adSize
        super.init()
    }

    override var credentials: MediationCredentials { StubCredentials(parameter: parameter) }
    override var adSize: AdSize { size }
}

// MARK: - Tests

/// Tests for the main `VelocityAdsGmaAdapter` lifecycle: `setUp` coalescing and the
/// lazy-init contract, and load-path validation.
///
/// Threading: the Google Mobile Ads SDK invokes load entry points on the main thread, and
/// `setUp` hops to the main queue itself. Running the tests on the main actor keeps the
/// load-path assertions synchronous; `setUp` assertions drain the main queue first.
@MainActor
final class VelocityAdsGmaAdapterTests: XCTestCase {

    private static let unitOnly = #"{"adUnitId":"unit-1"}"#
    private static let withAppKey = #"{"appKey":"app-1","adUnitId":"unit-1"}"#

    /// Delegates handed to the stubbed initSDK runner, so tests can drive the
    /// coalesced init flow to completion deterministically.
    private var capturedInitDelegates: [VelocityAdsInitDelegate] = []

    override func setUp() {
        super.setUp()
        capturedInitDelegates = []
        // Stub the SDK init trigger: unit tests must never perform real network
        // initialization. Individual tests complete the flow via the captured
        // delegate when they need a terminal outcome.
        VelocityAdsGmaAdapter.initSDKRunnerForTesting = { [weak self] _, delegate in
            self?.capturedInitDelegates.append(delegate)
        }
    }

    override func tearDown() {
        VelocityAdsGmaAdapter.resetInitStateForTesting()
        capturedInitDelegates = []
        super.tearDown()
    }

    /// Completes the in-flight stubbed init with a failure outcome.
    private func failInFlightInit() {
        for delegate in capturedInitDelegates {
            delegate.onInitFailure(error: VelocityAdsError(
                code: VelocityAdsErrorCode.internalError,
                message: "test-driven init failure"
            ))
        }
        capturedInitDelegates = []
    }

    /// `setUp(with:)` always hops to the main queue asynchronously; spin the run loop
    /// until the hop has executed.
    private func drainMainQueue() {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
    }

    // MARK: - setUp — lazy-init contract

    func test_setUp_withNoAppKeyInAnyMapping_reportsSuccessImmediately() {
        let configuration = StubServerConfiguration(parameters: [Self.unitOnly, nil, "bare-unit"])

        var completed = false
        var error: Error?
        VelocityAdsGmaAdapter.setUp(with: configuration) { result in
            completed = true
            error = result
        }

        XCTAssertTrue(completed, "Without an appKey the adapter must not block the Google Mobile Ads SDK")
        XCTAssertNil(error)
        XCTAssertTrue(capturedInitDelegates.isEmpty, "No SDK init may be started without an appKey")
    }

    func test_setUp_withEmptyConfiguration_reportsSuccessImmediately() {
        var completed = false
        VelocityAdsGmaAdapter.setUp(with: StubServerConfiguration(parameters: [])) { _ in completed = true }
        XCTAssertTrue(completed)
    }

    // MARK: - setUp — coalescing

    func test_setUp_simultaneousCalls_coalesceOntoOneInitAndShareTheOutcome() {
        let configuration = StubServerConfiguration(parameters: [Self.withAppKey])

        var outcome1: Error??
        var outcome2: Error??
        VelocityAdsGmaAdapter.setUp(with: configuration) { outcome1 = .some($0) }
        VelocityAdsGmaAdapter.setUp(with: configuration) { outcome2 = .some($0) }
        drainMainQueue()

        // Only the first caller triggers the SDK init; the second parks on the coalescer.
        XCTAssertEqual(capturedInitDelegates.count, 1, "Exactly one SDK init must be started for coalesced calls")
        XCTAssertNil(outcome1 as Any?, "First setUp handler must not fire before the SDK responds")
        XCTAssertNil(outcome2 as Any?, "Second setUp handler must not fire before the SDK responds")

        failInFlightInit()

        XCTAssertNotNil(outcome1 ?? nil, "Winner must receive the broadcast failure")
        XCTAssertNotNil(outcome2 ?? nil, "Parked caller must receive the broadcast failure")
    }

    func test_setUp_remembersAppKeyForLaterLoads() {
        VelocityAdsGmaAdapter.setUp(with: StubServerConfiguration(parameters: [Self.withAppKey])) { _ in }
        drainMainQueue()

        XCTAssertEqual(VelocityAdsGmaAdapter.storedAppKey, "app-1")
    }

    func test_rememberAppKey_keepsTheFirstKeyWhenALaterMappingDisagrees() {
        VelocityAdsGmaAdapter.rememberAppKey("app-1")
        VelocityAdsGmaAdapter.rememberAppKey("app-2")
        VelocityAdsGmaAdapter.rememberAppKey("app-3")

        XCTAssertEqual(VelocityAdsGmaAdapter.storedAppKey, "app-1")
    }

    func test_load_withMismatchedAppKey_initializesWithTheFirstKeySeen() {
        var capturedAppKeys: [String] = []
        VelocityAdsGmaAdapter.initSDKRunnerForTesting = { [weak self] request, delegate in
            capturedAppKeys.append(request.appKey)
            self?.capturedInitDelegates.append(delegate)
        }
        VelocityAdsGmaAdapter.setUp(with: StubServerConfiguration(parameters: [Self.withAppKey])) { _ in }
        drainMainQueue()
        failInFlightInit()

        VelocityAdsGmaAdapter().loadInterstitial(
            for: StubInterstitialConfiguration(parameter: #"{"appKey":"app-other","adUnitId":"unit-1"}"#)
        ) { _, _ in nil }

        XCTAssertEqual(capturedAppKeys, ["app-1", "app-1"])
    }

    func test_firstAppKey_returnsFirstNonBlankAcrossMappings() {
        let configuration = StubServerConfiguration(parameters: [
            nil,
            Self.unitOnly,
            #"{"appKey":"app-2","adUnitId":"unit-2"}"#,
            #"{"appKey":"app-3","adUnitId":"unit-3"}"#
        ])
        XCTAssertEqual(VelocityAdsGmaAdapter.firstAppKey(in: configuration), "app-2")
    }

    // MARK: - Load — server parameter guard

    func test_loadInterstitial_withMissingParameter_failsWithInvalidServerParameters() {
        let adapter = VelocityAdsGmaAdapter()
        var received: NSError?
        adapter.loadInterstitial(for: StubInterstitialConfiguration(parameter: nil)) { _, error in
            received = error as NSError?
            return nil
        }
        XCTAssertEqual(received?.domain, VelocityAdsErrorMapper.adapterDomain)
        XCTAssertEqual(received?.code, VelocityAdsErrorMapper.AdapterErrorCode.invalidServerParameters.rawValue)
    }

    func test_loadRewarded_withJSONLackingAdUnitId_failsWithInvalidServerParameters() {
        let adapter = VelocityAdsGmaAdapter()
        var received: NSError?
        adapter.loadRewardedAd(for: StubRewardedConfiguration(parameter: #"{"appKey":"app-1"}"#)) { _, error in
            received = error as NSError?
            return nil
        }
        XCTAssertEqual(received?.code, VelocityAdsErrorMapper.AdapterErrorCode.invalidServerParameters.rawValue)
    }

    func test_loadBanner_withMalformedParameter_failsWithInvalidServerParameters() {
        let adapter = VelocityAdsGmaAdapter()
        var received: NSError?
        adapter.loadBanner(for: StubBannerConfiguration(parameter: "{oops")) { _, error in
            received = error as NSError?
            return nil
        }
        XCTAssertEqual(received?.code, VelocityAdsErrorMapper.AdapterErrorCode.invalidServerParameters.rawValue)
    }

    func test_loadBanner_withFluidSize_failsWithInvalidAdSizeBeforeTouchingTheSDK() {
        let adapter = VelocityAdsGmaAdapter()
        var received: NSError?
        adapter.loadBanner(for: StubBannerConfiguration(parameter: Self.withAppKey, adSize: AdSizeFluid)) { _, error in
            received = error as NSError?
            return nil
        }
        XCTAssertEqual(received?.code, VelocityAdsErrorMapper.AdapterErrorCode.invalidAdSize.rawValue)
        XCTAssertTrue(capturedInitDelegates.isEmpty, "Size validation must fail fast, before any init attempt")
    }

    // MARK: - Load — not-initialized path
    //
    // The SDK is never initialized in the test process. With no appKey available (none in
    // the parameter, none remembered from setUp) ensureInitialized delivers false synchronously.

    func test_loadInterstitial_withoutAnyAppKey_failsWithSdkNotInitialized() {
        let adapter = VelocityAdsGmaAdapter()
        var received: NSError?
        adapter.loadInterstitial(for: StubInterstitialConfiguration(parameter: Self.unitOnly)) { _, error in
            received = error as NSError?
            return nil
        }
        XCTAssertEqual(received?.code, VelocityAdsErrorMapper.AdapterErrorCode.sdkNotInitialized.rawValue)
        XCTAssertTrue(capturedInitDelegates.isEmpty)
    }

    func test_loadRewarded_withoutAnyAppKey_failsWithSdkNotInitialized() {
        let adapter = VelocityAdsGmaAdapter()
        var received: NSError?
        adapter.loadRewardedAd(for: StubRewardedConfiguration(parameter: "bare-unit-id")) { _, error in
            received = error as NSError?
            return nil
        }
        XCTAssertEqual(received?.code, VelocityAdsErrorMapper.AdapterErrorCode.sdkNotInitialized.rawValue)
    }

    func test_loadBanner_withoutAnyAppKey_failsWithSdkNotInitialized() {
        let adapter = VelocityAdsGmaAdapter()
        var received: NSError?
        adapter.loadBanner(for: StubBannerConfiguration(parameter: Self.unitOnly)) { _, error in
            received = error as NSError?
            return nil
        }
        XCTAssertEqual(received?.code, VelocityAdsErrorMapper.AdapterErrorCode.sdkNotInitialized.rawValue)
    }

    // MARK: - Load — lazy init from the load-time appKey

    func test_loadInterstitial_withAppKey_startsInitAndFailsWithSdkNotInitializedWhenInitFails() {
        let adapter = VelocityAdsGmaAdapter()
        var received: NSError?
        var completed = false
        adapter.loadInterstitial(for: StubInterstitialConfiguration(parameter: Self.withAppKey)) { _, error in
            completed = true
            received = error as NSError?
            return nil
        }

        XCTAssertEqual(capturedInitDelegates.count, 1, "A load carrying an appKey must trigger lazy SDK init")
        XCTAssertFalse(completed, "The load must park until the init resolves")

        failInFlightInit()

        XCTAssertTrue(completed)
        XCTAssertEqual(received?.code, VelocityAdsErrorMapper.AdapterErrorCode.sdkNotInitialized.rawValue)
    }

    func test_load_usesAppKeyRememberedFromSetUp_whenParameterCarriesOnlyAdUnitId() {
        VelocityAdsGmaAdapter.setUp(with: StubServerConfiguration(parameters: [Self.withAppKey])) { _ in }
        drainMainQueue()
        XCTAssertEqual(capturedInitDelegates.count, 1)

        // A load with only an adUnitId must park on the in-flight init (not fail fast)
        // because a key is known from setUp.
        let adapter = VelocityAdsGmaAdapter()
        var completed = false
        var received: NSError?
        adapter.loadInterstitial(for: StubInterstitialConfiguration(parameter: Self.unitOnly)) { _, error in
            completed = true
            received = error as NSError?
            return nil
        }
        XCTAssertFalse(completed, "Load must park on the coalesced init")
        XCTAssertEqual(capturedInitDelegates.count, 1, "The parked load must not start a second init")

        failInFlightInit()

        XCTAssertTrue(completed)
        XCTAssertEqual(received?.code, VelocityAdsErrorMapper.AdapterErrorCode.sdkNotInitialized.rawValue)
    }

    func test_concurrentLoads_coalesceOntoOneInit() {
        let adapter1 = VelocityAdsGmaAdapter()
        let adapter2 = VelocityAdsGmaAdapter()
        var completions = 0
        adapter1.loadInterstitial(for: StubInterstitialConfiguration(parameter: Self.withAppKey)) { _, _ in
            completions += 1
            return nil
        }
        adapter2.loadRewardedAd(for: StubRewardedConfiguration(parameter: Self.withAppKey)) { _, _ in
            completions += 1
            return nil
        }

        XCTAssertEqual(capturedInitDelegates.count, 1, "Concurrent loads must share one SDK init")
        XCTAssertEqual(completions, 0)

        failInFlightInit()

        XCTAssertEqual(completions, 2, "Both parked loads must receive the broadcast outcome")
    }
}
