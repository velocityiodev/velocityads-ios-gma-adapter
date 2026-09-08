/// Coalesces concurrent SDK-init attempts so only one caller performs the
/// actual initialization while every other caller waits for its outcome.
///
/// Main-actor-confined: the Google Mobile Ads SDK delivers all adapter load entry points on the
/// main thread, and every adapter access goes through a main-actor context, so
/// no further synchronisation is required.
@MainActor
final class InitCoalescer<Outcome> {

    /// `true` while a claimed init attempt is in flight.
    private(set) var isClaimed = false

    private var pendingHandlers: [@MainActor (Outcome) -> Void] = []

    nonisolated init() {}

    /// Registers `handler` to receive the outcome of the in-flight (or about to
    /// start) init attempt.
    ///
    /// - Returns: `true` if the caller won the claim and must perform the init,
    ///   then broadcast via `complete(with:)`; `false` if the handler was parked
    ///   and will be invoked when the winner broadcasts.
    func claim(_ handler: @escaping @MainActor (Outcome) -> Void) -> Bool {
        pendingHandlers.append(handler)
        if isClaimed {
            return false
        }
        isClaimed = true
        return true
    }

    /// Broadcasts `outcome` to every registered handler (winner included, in
    /// registration order) and resets the claim so a later attempt can run —
    /// e.g. a re-init after a transient failure.
    func complete(with outcome: Outcome) {
        let handlers = pendingHandlers
        pendingHandlers = []
        isClaimed = false
        for handler in handlers {
            handler(outcome)
        }
    }
}
