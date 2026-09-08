/// Single source of truth for the adapter version string reported to the Google Mobile Ads SDK.
///
/// Four segments: the wrapped SDK's 3-segment semver plus a trailing adapter-build
/// segment. `VelocityAdsGmaAdapter.podspec` must carry the same value — bump both
/// together when releasing.
internal let velocityAdsGmaAdapterVersion = "0.10.0.0"

/// Mediation name reported to the Velocity SDK via `VelocityAdsMediationBridge`.
/// Owned by this adapter — the SDK accepts any lowercase canonical string.
internal let velocityAdsMediationName = "gma"

internal extension String {
    /// Returns `nil` when the string is empty, `self` otherwise.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
