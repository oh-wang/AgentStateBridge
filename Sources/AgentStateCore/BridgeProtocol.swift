import Foundation

public struct BridgeApplication: Codable, Equatable, Sendable {
    public let id: String
    public let bundleId: String
    public let version: String?

    public init(id: String, bundleId: String, version: String?) {
        self.id = id
        self.bundleId = bundleId
        self.version = version
    }
}

public struct AgentStateEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sequence: UInt64
    public let timestamp: Date
    public let application: BridgeApplication
    public let state: AgentActivityState
    public let previousState: AgentActivityState?
    public let confidence: Double
    public let evidence: [ActivityEvidence]

    public init(
        schemaVersion: Int = AgentStateEnvelope.currentSchemaVersion,
        sequence: UInt64,
        timestamp: Date,
        application: BridgeApplication,
        state: AgentActivityState,
        previousState: AgentActivityState?,
        confidence: Double,
        evidence: [ActivityEvidence]
    ) {
        self.schemaVersion = schemaVersion
        self.sequence = sequence
        self.timestamp = timestamp
        self.application = application
        self.state = state
        self.previousState = previousState
        self.confidence = confidence
        self.evidence = evidence
    }
}
