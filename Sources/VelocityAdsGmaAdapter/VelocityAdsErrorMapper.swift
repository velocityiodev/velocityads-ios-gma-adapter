import Foundation
import GoogleMobileAds
import VelocityAdsSDK

/// Builds the `NSError` values the adapter reports to the Google Mobile Ads SDK.
///
/// Two error domains are used:
/// - `adapterDomain` for conditions detected by the adapter itself (missing configuration,
///   SDK not initialized, ad not ready, unsupported size). Codes are the `AdapterErrorCode` cases.
/// - `sdkDomain` for errors raised by the Velocity SDK. The error code is the closest
///   `RequestError` category so AdMob reporting buckets it correctly; the original Velocity
///   code and message are preserved verbatim in `userInfo` (and as `NSUnderlyingErrorKey`)
///   so they stay visible in Ad Inspector and logs.
enum VelocityAdsErrorMapper {

    /// Domain for errors originating in this adapter.
    static let adapterDomain = "io.velocityads.gma"

    /// Domain for errors originating in the Velocity Ads SDK.
    static let sdkDomain = "io.velocityads.sdk"

    /// `userInfo` key carrying the original Velocity error code as an `Int`.
    static let velocityErrorCodeKey = "io.velocityads.gma.velocityErrorCode"

    enum AdapterErrorCode: Int {
        /// The custom event parameter is missing, malformed, or has no ad unit ID.
        case invalidServerParameters = 101
        /// The Velocity SDK could not be initialized before the load.
        case sdkNotInitialized = 102
        /// `present(from:)` was called with no loaded ad.
        case adNotReady = 103
        /// The requested banner size cannot be served by the Velocity SDK.
        case invalidAdSize = 104
    }

    // MARK: - Adapter-originated errors

    static func invalidServerParameters() -> NSError {
        adapterError(
            .invalidServerParameters,
            "Velocity Ads: the custom event parameter must be a JSON object with an \"adUnitId\" (and optional \"appKey\")."
        )
    }

    static func sdkNotInitialized() -> NSError {
        adapterError(
            .sdkNotInitialized,
            "Velocity Ads: SDK is not initialized. Provide an \"appKey\" in the custom event parameter or initialize the SDK in the app."
        )
    }

    static func adNotReady() -> NSError {
        adapterError(.adNotReady, "Velocity Ads: no ad is loaded and ready to show.")
    }

    static func invalidAdSize(_ description: String) -> NSError {
        adapterError(.invalidAdSize, "Velocity Ads: unsupported banner size \(description).")
    }

    // MARK: - Velocity SDK errors

    /// Maps a `VelocityAdsError` to an `NSError` whose code is the closest `RequestError`
    /// category, with the untouched Velocity code and message attached.
    static func map(_ error: VelocityAdsError) -> NSError {
        let category: RequestError.Code
        switch error.code {
        case VelocityAdsErrorCode.noFill:
            category = .noFill

        case VelocityAdsErrorCode.networkError,
             VelocityAdsErrorCode.httpFailure,
             VelocityAdsErrorCode.serverErrorField:
            category = .networkError

        case VelocityAdsErrorCode.invalidURL,
             VelocityAdsErrorCode.invalidAppKey,
             VelocityAdsErrorCode.invalidAdUnitId,
             VelocityAdsErrorCode.sdkNotInitialized,
             VelocityAdsErrorCode.sdkInitializationInProgress,
             VelocityAdsErrorCode.loadAlreadyInProgress,
             VelocityAdsErrorCode.adAlreadyLoaded,
             VelocityAdsErrorCode.adSpent,
             VelocityAdsErrorCode.adDestroyed:
            category = .invalidRequest

        // Parse / response-shape failures, service unavailability, waterfall
        // exhaustion, and anything unknown are internal to the Velocity SDK.
        default:
            category = .internalError
        }

        let underlying = NSError(
            domain: sdkDomain,
            code: error.code,
            userInfo: [NSLocalizedDescriptionKey: error.message]
        )
        return NSError(
            domain: sdkDomain,
            code: category.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Velocity Ads [\(error.code)]: \(error.message)",
                velocityErrorCodeKey: error.code,
                NSUnderlyingErrorKey: underlying
            ]
        )
    }

    // MARK: - Private

    private static func adapterError(_ code: AdapterErrorCode, _ message: String) -> NSError {
        NSError(domain: adapterDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
