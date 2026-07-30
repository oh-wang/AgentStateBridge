import AgentStateCore
import XCTest

final class ActivityInferrerTests: XCTestCase {
    func testStopButtonMeansWorking() {
        let result = ActivityInferrer.assess(
            snapshot: snapshot(nodes: [node(semantic: .stopButton)]),
            previous: nil
        )

        XCTAssertEqual(result.state, .working)
        XCTAssertEqual(result.confidence, 0.96)
    }

    func testReasoningLiveRegionTakesPriorityOverStopButton() {
        let result = ActivityInferrer.assess(
            snapshot: snapshot(
                nodes: [
                    node(semantic: .stopButton),
                    node(semantic: .reasoningLabel, ariaLive: "polite")
                ]
            ),
            previous: nil
        )

        XCTAssertEqual(result.state, .reasoning)
        XCTAssertEqual(result.confidence, 0.94)
    }

    func testReasoningLabelDoesNotNeedLiveRegion() {
        let result = ActivityInferrer.assess(
            snapshot: snapshot(
                nodes: [
                    node(semantic: .stopButton),
                    node(semantic: .reasoningLabel)
                ]
            ),
            previous: nil
        )

        XCTAssertEqual(result.state, .reasoning)
    }

    func testReasoningLabelWithoutActiveAnswerIsIgnored() {
        let result = ActivityInferrer.assess(
            snapshot: snapshot(
                nodes: [
                    node(semantic: .reasoningLabel),
                    node(semantic: .promptInput)
                ]
            ),
            previous: nil
        )

        XCTAssertEqual(result.state, .idle)
    }

    func testTextInPromptMeansComposing() {
        let result = ActivityInferrer.assess(
            snapshot: snapshot(nodes: [node(semantic: .promptInput, hasUserText: true)]),
            previous: nil
        )

        XCTAssertEqual(result.state, .composing)
    }

    func testEmptyPromptMeansIdle() {
        let result = ActivityInferrer.assess(
            snapshot: snapshot(nodes: [node(semantic: .promptInput, hasUserText: false)]),
            previous: nil
        )

        XCTAssertEqual(result.state, .idle)
    }

    func testMissingStopButtonAfterWorkingMeansCompleted() {
        let working = ActivityAssessment(
            state: .working,
            confidence: 0.96,
            evidence: [.stopButtonPresent]
        )
        let result = ActivityInferrer.assess(
            snapshot: snapshot(nodes: [node(semantic: .promptInput)]),
            previous: working
        )

        XCTAssertEqual(result.state, .completed)
    }

    func testCompletedSurvivesExtraSnapshotsUntilCallerEndsTTL() {
        let completed = ActivityAssessment(
            state: .completed,
            confidence: 0.90,
            evidence: [.stopButtonDisappeared]
        )
        let result = ActivityInferrer.assess(
            snapshot: snapshot(nodes: [node(semantic: .promptInput)]),
            previous: completed
        )

        XCTAssertEqual(result, completed)
    }

    func testTypingInterruptsCompletedTTLImmediately() {
        let completed = ActivityAssessment(
            state: .completed,
            confidence: 0.90,
            evidence: [.stopButtonDisappeared]
        )
        let result = ActivityInferrer.assess(
            snapshot: snapshot(
                nodes: [node(semantic: .promptInput, hasUserText: true)]
            ),
            previous: completed
        )

        XCTAssertEqual(result.state, .composing)
    }

    func testNewWorkInterruptsCompletedTTLImmediately() {
        let completed = ActivityAssessment(
            state: .completed,
            confidence: 0.90,
            evidence: [.stopButtonDisappeared]
        )
        let result = ActivityInferrer.assess(
            snapshot: snapshot(nodes: [node(semantic: .stopButton)]),
            previous: completed
        )

        XCTAssertEqual(result.state, .working)
    }

    private func snapshot(nodes: [InspectedNode]) -> InspectionSnapshot {
        InspectionSnapshot(
            capturedAt: Date(timeIntervalSince1970: 0),
            applicationVersion: "test",
            processIdentifier: 1,
            nodes: nodes,
            wasTruncated: false
        )
    }

    private func node(
        semantic: ControlSemantic,
        hasUserText: Bool? = nil,
        ariaLive: String? = nil
    ) -> InspectedNode {
        InspectedNode(
            id: UUID().uuidString,
            depth: 0,
            role: "test",
            subrole: nil,
            identifier: nil,
            title: nil,
            description: nil,
            help: nil,
            valueSummary: nil,
            isEnabled: true,
            isFocused: false,
            childCount: 0,
            semantic: semantic,
            hasUserText: hasUserText,
            ariaLive: ariaLive
        )
    }
}
