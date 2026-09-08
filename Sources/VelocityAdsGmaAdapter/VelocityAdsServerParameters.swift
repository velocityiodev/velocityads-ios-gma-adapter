import Foundation
import GoogleMobileAds

/// The Velocity configuration carried by the single custom event **parameter** string
/// that the AdMob UI passes to the adapter.
///
/// Accepted formats:
/// - JSON object — `{"appKey":"<velocity app key>","adUnitId":"<velocity ad unit id>"}`.
///   `appKey` is optional when the host app initializes the Velocity SDK itself.
/// - Bare string — treated as the ad unit ID alone (no app key).
///
/// Blank values are normalised to `nil` so callers only need a single nil check.
struct VelocityAdsServerParameters: Equatable {

    static let appKeyKey = "appKey"
    static let adUnitIdKey = "adUnitId"

    static let empty = VelocityAdsServerParameters(appKey: nil, adUnitId: nil)

    let appKey: String?
    let adUnitId: String?

    /// Parses the raw custom event parameter. Never throws: malformed JSON that starts
    /// with `{` yields `.empty`; any other non-blank string is taken as a bare ad unit ID.
    static func parse(_ raw: String?) -> VelocityAdsServerParameters {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return .empty
        }
        guard trimmed.hasPrefix("{") else {
            return VelocityAdsServerParameters(appKey: nil, adUnitId: trimmed)
        }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return .empty
        }
        return VelocityAdsServerParameters(
            appKey: nonBlank(json[appKeyKey]),
            adUnitId: nonBlank(json[adUnitIdKey])
        )
    }

    /// Reads and parses the parameter from the credentials the Google Mobile Ads SDK attaches
    /// to a load-time or setup-time configuration.
    static func parse(credentials: MediationCredentials) -> VelocityAdsServerParameters {
        parse(credentials.settings[GADCustomEventParametersServer] as? String)
    }

    private static func nonBlank(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}
