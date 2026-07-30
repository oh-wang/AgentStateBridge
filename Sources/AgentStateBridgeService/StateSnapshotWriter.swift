import AgentStateCore
import Foundation

public struct StateSnapshotWriter: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = StateSnapshotWriter.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("AgentStateBridge", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    public func write(_ envelope: AgentStateEnvelope) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )

        let data = try AgentStateProtocolCodec.encode(envelope)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func read() throws -> AgentStateEnvelope {
        let data = try Data(contentsOf: fileURL)
        return try AgentStateProtocolCodec.decode(data)
    }
}
