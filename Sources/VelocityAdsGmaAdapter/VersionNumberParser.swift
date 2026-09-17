import GoogleMobileAds

/// Converts dotted version strings into the `VersionNumber` structure the Google Mobile Ads
/// SDK expects from mediation adapters.
enum VersionNumberParser {

    /// Parses the 4-segment adapter version `A.B.C.D` following Google's mediation-adapter
    /// convention: major `A`, minor `B`, patch `C * 100 + D`, so the adapter-build segment
    /// stays visible alongside the wrapped SDK patch version.
    static func adapterVersion(_ version: String) -> VersionNumber {
        let parts = segments(version)
        guard parts.count >= 4 else { return VersionNumber() }
        return VersionNumber(majorVersion: parts[0], minorVersion: parts[1], patchVersion: parts[2] * 100 + parts[3])
    }

    /// Parses a 3-segment (or longer) SDK version `A.B.C` into major / minor / patch.
    static func sdkVersion(_ version: String) -> VersionNumber {
        let parts = segments(version)
        guard parts.count >= 3 else { return VersionNumber() }
        return VersionNumber(majorVersion: parts[0], minorVersion: parts[1], patchVersion: parts[2])
    }

    private static func segments(_ version: String) -> [Int] {
        let numeric = version.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-").first ?? ""
        return numeric.split(separator: ".").compactMap { Int($0) }
    }
}
