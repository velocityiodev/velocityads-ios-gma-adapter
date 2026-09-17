import os.log

/// Unified logging for the adapter. Only warnings are emitted — conditions that have no
/// Google Mobile Ads counterpart and would otherwise be invisible to the publisher.
enum AdapterLog {

    private static let log = OSLog(subsystem: "io.velocityads.gma", category: "VelocityAdsGmaAdapter")

    static func warn(_ message: String) {
        os_log("%{public}@", log: log, type: .error, message)
    }
}
