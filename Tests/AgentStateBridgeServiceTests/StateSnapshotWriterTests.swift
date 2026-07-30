import AgentStateBridgeService
import AgentStateCore
import Darwin
import Foundation
import XCTest

final class StateSnapshotWriterTests: XCTestCase {
    func testProtocolRoundTrip() throws {
        let snapshot = makeSnapshot(sequence: 7)
        let data = try AgentStateProtocolCodec.encode(snapshot)
        let decoded = try AgentStateProtocolCodec.decode(data)

        XCTAssertEqual(decoded, snapshot)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(text.contains("\"state\" : \"working\""))
        XCTAssertFalse(text.contains("prompt"))
    }

    func testWriterCreatesPrivateAtomicSnapshot() throws {
        try withTemporaryWriter { writer in
            let snapshot = makeSnapshot(sequence: 8)
            try writer.write(snapshot)

            XCTAssertEqual(try writer.read(), snapshot)

            let attributes = try FileManager.default.attributesOfItem(
                atPath: writer.fileURL.path
            )
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
            XCTAssertEqual(permissions.intValue, 0o600)
        }
    }

    func testPublisherIncrementsSequenceAndRestoresItAfterRestart() throws {
        try withTemporaryWriter { writer in
            let firstPublisher = StateSnapshotPublisher(writer: writer)
            let first = try firstPublisher.publish(
                assessment: workingAssessment,
                previousState: .composing,
                applicationVersion: "test",
                timestamp: Date(timeIntervalSince1970: 1)
            )
            let second = try firstPublisher.publish(
                assessment: idleAssessment,
                previousState: .working,
                applicationVersion: "test",
                timestamp: Date(timeIntervalSince1970: 2)
            )
            let restartedPublisher = StateSnapshotPublisher(writer: writer)
            let third = try restartedPublisher.publish(
                assessment: idleAssessment,
                previousState: nil,
                applicationVersion: "test",
                timestamp: Date(timeIntervalSince1970: 3)
            )

            XCTAssertEqual(first.sequence, 1)
            XCTAssertEqual(second.sequence, 2)
            XCTAssertEqual(third.sequence, 3)
        }
    }

    func testStreamFrameIsOneJSONLine() throws {
        let snapshot = makeSnapshot(sequence: 9)
        let frame = try AgentStateProtocolCodec.encodeStreamFrame(snapshot)
        let text = try XCTUnwrap(String(data: frame, encoding: .utf8))

        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(text.filter { $0 == "\n" }.count, 1)
        XCTAssertEqual(
            try AgentStateProtocolCodec.decode(Data(frame.dropLast())),
            snapshot
        )
    }

    func testUnixSocketSendsLatestAndFollowingStates() throws {
        let directory = URL(
            fileURLWithPath: "/tmp/asb-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        let socketURL = directory.appendingPathComponent("bridge.sock")
        let server = UnixSocketStateServer(socketURL: socketURL)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        try server.start()
        try server.broadcast(makeSnapshot(sequence: 10))

        let attributes = try FileManager.default.attributesOfItem(
            atPath: socketURL.path
        )
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSocket)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o600)

        let client = try connectUnixSocket(path: socketURL.path)
        defer { Darwin.close(client) }
        let line = try receiveLine(from: client)
        let received = try AgentStateProtocolCodec.decode(line)
        XCTAssertEqual(received.sequence, 10)
        XCTAssertEqual(received.state, .working)

        try server.broadcast(makeSnapshot(sequence: 11))
        let nextLine = try receiveLine(from: client)
        let next = try AgentStateProtocolCodec.decode(nextLine)
        XCTAssertEqual(next.sequence, 11)
    }

    func testUnixSocketReleasesClientsImmediatelyAfterEOF() throws {
        let directory = URL(
            fileURLWithPath: "/tmp/asb-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        let socketURL = directory.appendingPathComponent("bridge.sock")
        let server = UnixSocketStateServer(socketURL: socketURL)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        try server.start()
        try server.broadcast(makeSnapshot(sequence: 12))

        for _ in 0..<50 {
            let client = try connectUnixSocket(path: socketURL.path)
            _ = try receiveLine(from: client)
            Darwin.close(client)
        }

        let deadline = Date().addingTimeInterval(2)
        while server.connectedClientCount != 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(server.connectedClientCount, 0)
    }

    private var workingAssessment: ActivityAssessment {
        ActivityAssessment(
            state: .working,
            confidence: 0.96,
            evidence: [.stopButtonPresent]
        )
    }

    private var idleAssessment: ActivityAssessment {
        ActivityAssessment(
            state: .idle,
            confidence: 0.82,
            evidence: [.promptInputPresent]
        )
    }

    private func makeSnapshot(sequence: UInt64) -> AgentStateEnvelope {
        AgentStateEnvelope(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: 10),
            application: BridgeApplication(
                id: "chatgpt",
                bundleId: "com.openai.codex",
                version: "test"
            ),
            state: .working,
            previousState: .composing,
            confidence: 0.96,
            evidence: [.stopButtonPresent]
        )
    }

    private func withTemporaryWriter(
        _ body: (StateSnapshotWriter) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentStateBridgeTests-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("state.json")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try body(StateSnapshotWriter(fileURL: fileURL))
    }

    private func connectUnixSocket(path: String) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXError(.ECONNREFUSED)
        }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        Darwin.setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout.size(ofValue: timeout))
        )

        var address = sockaddr_un()
        let pathBytes = Array(path.utf8CString)
        let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 2
        let addressLength = socklen_t(pathOffset + pathBytes.count)
        address.sun_len = UInt8(addressLength)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                _ = memcpy(destination, source.baseAddress, source.count)
            }
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, addressLength)
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .ECONNREFUSED)
        }
        return descriptor
    }

    private func receiveLine(from descriptor: Int32) throws -> Data {
        var result = Data()
        var byte: UInt8 = 0
        while true {
            let count = Darwin.recv(descriptor, &byte, 1, 0)
            guard count == 1 else {
                throw POSIXError(.ETIMEDOUT)
            }
            if byte == 0x0A {
                return result
            }
            result.append(byte)
        }
    }
}
