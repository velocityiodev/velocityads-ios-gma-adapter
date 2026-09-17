import XCTest

@testable import VelocityAdsGmaAdapter

@MainActor
final class InitCoalescerTests: XCTestCase {

    private enum Outcome: Equatable {
        case success
        case failure
    }

    private var coalescer: InitCoalescer<Outcome>!

    override func setUp() {
        super.setUp()
        coalescer = InitCoalescer<Outcome>()
    }

    override func tearDown() {
        coalescer = nil
        super.tearDown()
    }

    // ========== Claiming ==========

    func test_claim_firstCaller_winsAndSetsClaimed() {
        // When
        let won = coalescer.claim { _ in }

        // Then
        XCTAssertTrue(won, "First caller must win the claim")
        XCTAssertTrue(coalescer.isClaimed)
    }

    func test_claim_whileClaimed_parksHandlerAndReturnsFalse() {
        // Given
        _ = coalescer.claim { _ in }

        // When
        let secondWon = coalescer.claim { _ in }
        let thirdWon = coalescer.claim { _ in }

        // Then
        XCTAssertFalse(secondWon, "Callers arriving while claimed must be parked")
        XCTAssertFalse(thirdWon, "Callers arriving while claimed must be parked")
        XCTAssertTrue(coalescer.isClaimed)
    }

    // ========== Broadcasting ==========

    func test_complete_broadcastsOutcomeToAllHandlersInRegistrationOrder() {
        // Given
        var received: [(index: Int, outcome: Outcome)] = []
        _ = coalescer.claim { received.append((0, $0)) }
        _ = coalescer.claim { received.append((1, $0)) }
        _ = coalescer.claim { received.append((2, $0)) }

        // When
        coalescer.complete(with: .success)

        // Then
        XCTAssertEqual(received.map(\.index), [0, 1, 2], "All parked handlers must drain in order")
        XCTAssertTrue(received.allSatisfy { $0.outcome == .success })
    }

    func test_complete_drainsHandlers_soASecondCompleteInvokesNothing() {
        // Given
        var invocationCount = 0
        _ = coalescer.claim { _ in invocationCount += 1 }
        _ = coalescer.claim { _ in invocationCount += 1 }
        coalescer.complete(with: .success)

        // When
        coalescer.complete(with: .failure)

        // Then
        XCTAssertEqual(invocationCount, 2, "Handlers must be invoked exactly once")
    }

    // ========== Claim reset ==========

    func test_complete_onSuccess_resetsClaim_soNextCallerWinsAgain() {
        // Given
        _ = coalescer.claim { _ in }
        coalescer.complete(with: .success)

        // When / Then
        XCTAssertFalse(coalescer.isClaimed, "Claim must reset after a successful broadcast")
        XCTAssertTrue(coalescer.claim { _ in }, "Next caller after completion must win a fresh claim")
    }

    func test_complete_onFailure_resetsClaim_soReInitCanBeAttempted() {
        // Given
        _ = coalescer.claim { _ in }
        coalescer.complete(with: .failure)

        // When / Then
        XCTAssertFalse(coalescer.isClaimed, "Claim must reset after a failed broadcast")
        XCTAssertTrue(coalescer.claim { _ in }, "A re-init attempt after failure must win a fresh claim")
    }

    func test_reclaimAfterFailure_parksNewHandlersIndependently() {
        // Given — first round fails
        var firstRound: [Outcome] = []
        _ = coalescer.claim { firstRound.append($0) }
        coalescer.complete(with: .failure)

        // When — second round succeeds
        var secondRound: [Outcome] = []
        _ = coalescer.claim { secondRound.append($0) }
        _ = coalescer.claim { secondRound.append($0) }
        coalescer.complete(with: .success)

        // Then
        XCTAssertEqual(firstRound, [.failure])
        XCTAssertEqual(secondRound, [.success, .success])
    }
}
