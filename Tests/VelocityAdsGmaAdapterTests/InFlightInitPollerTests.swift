import XCTest

@testable import VelocityAdsGmaAdapter

@MainActor
final class InFlightInitPollerTests: XCTestCase {

    private var pendingTicks: [@MainActor () -> Void] = []
    private var results: [Bool] = []

    override func setUp() {
        super.setUp()
        pendingTicks = []
        results = []
    }

    /// Starts the poller with a manual scheduler so each poll tick runs only
    /// when the test calls `runNextTick()`.
    private func startPoller(
        isInitialized: @escaping @MainActor () -> Bool,
        pollInterval: TimeInterval = 0.2,
        timeout: TimeInterval = 1.0
    ) {
        InFlightInitPoller.awaitInitialization(
            isInitialized: isInitialized,
            pollInterval: pollInterval,
            timeout: timeout,
            schedule: { [self] _, block in pendingTicks.append(block) },
            completion: { [self] outcome in results.append(outcome) }
        )
    }

    private func runNextTick() {
        pendingTicks.removeFirst()()
    }

    // ========== Immediate success ==========

    func test_alreadyInitializedAtFirstCheck_completesSuccessWithoutScheduling() {
        // When
        startPoller(isInitialized: { true })

        // Then
        XCTAssertEqual(results, [true], "Must complete synchronously when already initialized")
        XCTAssertTrue(pendingTicks.isEmpty, "No poll ticks must be scheduled")
    }

    // ========== Becomes initialized mid-poll ==========

    func test_becomesInitializedMidPoll_completesWithSuccess() {
        // Given
        var initialized = false
        startPoller(isInitialized: { initialized })

        // When — two ticks pass while still uninitialized
        runNextTick()
        runNextTick()
        XCTAssertEqual(results, [], "Must not complete while uninitialized and within deadline")

        // The in-flight (host-app) init finishes before the next tick.
        initialized = true
        runNextTick()

        // Then
        XCTAssertEqual(results, [true], "Must complete with success once initialization is observed")
        XCTAssertTrue(pendingTicks.isEmpty, "No further ticks must be scheduled after completion")
    }

    // ========== Timeout ==========

    func test_neverInitialized_completesWithTimeoutFailureAfterPollBudget() {
        // Given — timeout 1.0s / interval 0.2s → exactly 5 poll ticks
        startPoller(isInitialized: { false })

        // When — drain every scheduled tick
        var ticksRun = 0
        while !pendingTicks.isEmpty {
            runNextTick()
            ticksRun += 1
        }

        // Then
        XCTAssertEqual(ticksRun, 5, "Poll budget must match timeout / pollInterval")
        XCTAssertEqual(results, [false], "Must complete with failure once the deadline passes")
    }

    // ========== Exactly-once completion ==========

    func test_completionFiresExactlyOnce_onSuccessPath() {
        // Given
        var initialized = false
        startPoller(isInitialized: { initialized })
        initialized = true

        // When — drain any remaining ticks after completion
        while !pendingTicks.isEmpty {
            runNextTick()
        }

        // Then
        XCTAssertEqual(results, [true], "Completion must fire exactly once")
    }

    func test_completionFiresExactlyOnce_onTimeoutPath_evenIfInitializedLater() {
        // Given — poller runs to timeout
        var initialized = false
        startPoller(isInitialized: { initialized })
        while !pendingTicks.isEmpty {
            runNextTick()
        }
        XCTAssertEqual(results, [false])

        // When — initialization completes after the deadline already fired
        initialized = true

        // Then — nothing is scheduled anymore, so no second completion can occur
        XCTAssertTrue(pendingTicks.isEmpty, "No ticks may remain after the timeout completion")
        XCTAssertEqual(results, [false], "Completion must not fire a second time")
    }
}
