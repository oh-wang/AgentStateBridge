import AgentStateCore
import Foundation

public final class StateSnapshotPublisher {
    public let writer: StateSnapshotWriter
    private var nextSequence: UInt64

    public init(writer: StateSnapshotWriter = StateSnapshotWriter()) {
        self.writer = writer
        if let previous = try? writer.read() {
            nextSequence = previous.sequence &+ 1
        } else {
            nextSequence = 1
        }
    }

    @discardableResult
    public func publish(
        assessment: ActivityAssessment,
        previousState: AgentActivityState?,
        applicationVersion: String?,
        timestamp: Date = Date()
    ) throws -> AgentStateEnvelope {
        let envelope = makeEnvelope(
            assessment: assessment,
            previousState: previousState,
            applicationVersion: applicationVersion,
            timestamp: timestamp
        )
        try writer.write(envelope)
        return envelope
    }

    public func makeEnvelope(
        assessment: ActivityAssessment,
        previousState: AgentActivityState?,
        applicationVersion: String?,
        timestamp: Date = Date()
    ) -> AgentStateEnvelope {
        let envelope = AgentStateEnvelope(
            sequence: nextSequence,
            timestamp: timestamp,
            application: BridgeApplication(
                id: "chatgpt",
                bundleId: "com.openai.codex",
                version: applicationVersion
            ),
            state: assessment.state,
            previousState: previousState,
            confidence: assessment.confidence,
            evidence: assessment.evidence
        )

        nextSequence &+= 1
        return envelope
    }
}
