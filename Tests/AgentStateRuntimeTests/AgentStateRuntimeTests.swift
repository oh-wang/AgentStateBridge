import AgentStateBridgeService
import AgentStateCore
@testable import AgentStateRuntime
import XCTest

@MainActor
final class AgentStateRuntimeTests: XCTestCase {
    func testInspectionIntervalsKeepIdleWakeUpWithinHalfASecond() {
        XCTAssertEqual(
            AgentStateRuntime.inspectionIntervalMilliseconds(for: .idle),
            500
        )
        XCTAssertEqual(
            AgentStateRuntime.inspectionIntervalMilliseconds(for: .unknown),
            500
        )
        XCTAssertEqual(
            AgentStateRuntime.inspectionIntervalMilliseconds(for: .working),
            150
        )
        XCTAssertEqual(
            AgentStateRuntime.inspectionIntervalMilliseconds(for: .reasoning),
            150
        )
    }

    func testInspectionRefreshGateCoalescesRequests() {
        var gate = InspectionRefreshGate()

        XCTAssertTrue(gate.request())
        XCTAssertTrue(gate.isRunning)
        XCTAssertFalse(gate.request())
        XCTAssertFalse(gate.request())
        XCTAssertTrue(gate.finish())
        XCTAssertFalse(gate.isRunning)

        XCTAssertTrue(gate.request())
        XCTAssertFalse(gate.finish())
    }

    func testInspectionRefreshGateCancelDropsPendingRequest() {
        var gate = InspectionRefreshGate()

        XCTAssertTrue(gate.request())
        XCTAssertFalse(gate.request())
        gate.cancel()

        XCTAssertFalse(gate.isRunning)
        XCTAssertTrue(gate.request())
        XCTAssertFalse(gate.finish())
    }

    func testRuntimeSnapshotMatchesFrontendContract() {
        let envelope = AgentStateEnvelope(
            sequence: 42,
            timestamp: Date(timeIntervalSince1970: 0),
            application: BridgeApplication(
                id: "chatgpt",
                bundleId: "com.openai.codex",
                version: "test"
            ),
            state: .reasoning,
            previousState: .composing,
            confidence: 0.94,
            evidence: [.reasoningLabelPresent, .stopButtonPresent]
        )

        XCTAssertEqual(
            AgentStateRuntimeSnapshot(envelope: envelope),
            AgentStateRuntimeSnapshot(
                schemaVersion: 1,
                sequence: 42,
                state: "reasoning",
                previousState: "composing"
            )
        )
    }

    func testStartAndStopAreIdempotentAndStopPublishesSafeState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentStateRuntimeTests-\(UUID().uuidString)")
        let writer = StateSnapshotWriter(
            fileURL: directory.appendingPathComponent("state.json")
        )
        let publisher = StateSnapshotPublisher(writer: writer)
        let runtime = AgentStateRuntime(
            configuration: .init(enablesExternalSocket: false),
            statePublisher: publisher,
            socketServer: UnixSocketStateServer(
                socketURL: directory.appendingPathComponent("bridge.sock")
            )
        )
        defer {
            runtime.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        var received: [AgentStateRuntimeSnapshot] = []
        runtime.onSnapshot = { received.append($0) }

        runtime.start()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("bridge.sock").path
        ))
        let countAfterStart = received.count
        runtime.start()
        XCTAssertEqual(received.count, countAfterStart)

        runtime.stop()
        let countAfterStop = received.count
        runtime.stop()
        XCTAssertEqual(received.count, countAfterStop)
        XCTAssertEqual(received.last?.state, "unknown")
        XCTAssertEqual(try writer.read().state, .unknown)
        XCTAssertFalse(runtime.isRunning)
        XCTAssertFalse(runtime.isObserving)
    }

    func testStopRemovesExternalSocketAndLeavesSafeSnapshot() throws {
        let directory = URL(
            fileURLWithPath: "/tmp/asbrt-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        let writer = StateSnapshotWriter(
            fileURL: directory.appendingPathComponent("state.json")
        )
        let socketURL = directory.appendingPathComponent("bridge.sock")
        let runtime = AgentStateRuntime(
            configuration: .init(enablesExternalSocket: true),
            statePublisher: StateSnapshotPublisher(writer: writer),
            socketServer: UnixSocketStateServer(socketURL: socketURL)
        )
        defer {
            runtime.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        runtime.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketURL.path))

        runtime.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
        XCTAssertEqual(try writer.read().state, .unknown)
    }
}
