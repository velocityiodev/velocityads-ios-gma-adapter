import Foundation

/// Polls an initialization predicate on the main queue until it reports `true`
/// or a deadline passes.
///
/// Used when the Velocity SDK rejects the adapter's `initSDK` call with
/// SDK_INITIALIZATION_IN_PROGRESS (2002) because the host app started its own
/// initialization moments earlier. That rejection is not a permanent failure —
/// the in-flight init will finish shortly — so instead of reporting
/// a setup failure to the Google Mobile Ads SDK, the adapter waits for the real outcome.
///
/// `completion` is invoked exactly once: every poll iteration either terminates
/// with a completion call or reschedules itself, never both.
@MainActor
enum InFlightInitPoller {

    static let defaultPollInterval: TimeInterval = 0.2
    static let defaultTimeout: TimeInterval = 5.0

    /// Schedules `block` to run on the main actor after `delay` seconds.
    /// Injectable so tests can drive the polling loop deterministically.
    typealias Scheduler = @MainActor (_ delay: TimeInterval, _ block: @escaping @MainActor () -> Void) -> Void

    private static let mainQueueScheduler: Scheduler = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated(block)
        }
    }

    /// Starts polling `isInitialized`. Calls `completion(true)` as soon as the
    /// predicate returns `true`, or `completion(false)` once `timeout` elapses.
    ///
    /// Default parameter values cannot reference `@MainActor` statics (they are
    /// evaluated in a nonisolated context), so `nil` means “use the MainActor
    /// defaults” and is resolved inside this method.
    static func awaitInitialization(
        isInitialized: @escaping @MainActor () -> Bool,
        pollInterval: TimeInterval? = nil,
        timeout: TimeInterval? = nil,
        schedule: Scheduler? = nil,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let pollInterval = pollInterval ?? defaultPollInterval
        let timeout = timeout ?? defaultTimeout
        let schedule = schedule ?? mainQueueScheduler
        // Integer poll budget avoids floating-point drift from repeatedly
        // subtracting the interval from the remaining time.
        let totalPolls = pollInterval > 0 ? max(0, Int((timeout / pollInterval).rounded())) : 0
        poll(
            remainingPolls: totalPolls,
            isInitialized: isInitialized,
            pollInterval: pollInterval,
            schedule: schedule,
            completion: completion
        )
    }

    private static func poll(
        remainingPolls: Int,
        isInitialized: @escaping @MainActor () -> Bool,
        pollInterval: TimeInterval,
        schedule: @escaping Scheduler,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if isInitialized() {
            completion(true)
            return
        }
        guard remainingPolls > 0 else {
            completion(false)
            return
        }
        schedule(pollInterval) {
            poll(
                remainingPolls: remainingPolls - 1,
                isInitialized: isInitialized,
                pollInterval: pollInterval,
                schedule: schedule,
                completion: completion
            )
        }
    }
}
