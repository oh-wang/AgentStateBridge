import AgentStateCore
import Darwin
import Dispatch
import Foundation

public enum UnixSocketStateServerError: LocalizedError {
    case pathTooLong(String)
    case pathOccupied(String)
    case systemCall(String, Int32)
    case notStarted

    public var errorDescription: String? {
        switch self {
        case let .pathTooLong(path):
            return "Unix socket 路径过长：\(path)"
        case let .pathOccupied(path):
            return "Unix socket 已被其他程序占用：\(path)"
        case let .systemCall(name, code):
            return "\(name) 失败：\(String(cString: strerror(code)))"
        case .notStarted:
            return "Unix socket 服务尚未启动。"
        }
    }
}

/// Broadcasts newline-delimited AgentStateEnvelope JSON to local clients.
public final class UnixSocketStateServer: @unchecked Sendable {
    public let socketURL: URL

    private let queue = DispatchQueue(label: "AgentStateBridge.UnixSocket")
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var latestFrame: Data?
    private var isRunning = false

    public init(socketURL: URL = UnixSocketStateServer.defaultSocketURL()) {
        self.socketURL = socketURL
    }

    public var connectedClientCount: Int {
        queue.sync { clientSources.count }
    }

    public static func defaultSocketURL(
        fileManager: FileManager = .default
    ) -> URL {
        StateSnapshotWriter.defaultFileURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("bridge.sock", isDirectory: false)
    }

    public func start() throws {
        guard !isRunning else { return }

        let fileManager = FileManager.default
        let directoryURL = socketURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )

        if fileManager.fileExists(atPath: socketURL.path) {
            let attributes = try fileManager.attributesOfItem(atPath: socketURL.path)
            guard attributes[.type] as? FileAttributeType == .typeSocket else {
                throw UnixSocketStateServerError.pathOccupied(socketURL.path)
            }
            guard !Self.canConnect(to: socketURL.path) else {
                throw UnixSocketStateServerError.pathOccupied(socketURL.path)
            }
            try fileManager.removeItem(at: socketURL)
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw UnixSocketStateServerError.systemCall("socket", errno)
        }

        do {
            try Self.bind(descriptor: descriptor, path: socketURL.path)
            guard Darwin.listen(descriptor, 16) == 0 else {
                throw UnixSocketStateServerError.systemCall("listen", errno)
            }
            try Self.makeNonBlocking(descriptor)
            guard Darwin.chmod(socketURL.path, 0o600) == 0 else {
                throw UnixSocketStateServerError.systemCall("chmod", errno)
            }
        } catch {
            Darwin.close(descriptor)
            try? fileManager.removeItem(at: socketURL)
            throw error
        }

        listener = descriptor
        isRunning = true
        let newSource = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: queue
        )
        newSource.setEventHandler { [weak self] in
            self?.acceptAvailableClients()
        }
        source = newSource
        newSource.resume()
    }

    public func broadcast(_ envelope: AgentStateEnvelope) throws {
        guard isRunning else {
            throw UnixSocketStateServerError.notStarted
        }
        let frame = try AgentStateProtocolCodec.encodeStreamFrame(envelope)
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.latestFrame = frame
            self.send(frame, toAll: Array(self.clientSources.keys))
        }
    }

    public func stop() {
        guard isRunning else { return }
        queue.sync {
            isRunning = false
            source?.setEventHandler {}
            source?.cancel()
            source = nil

            for client in Array(clientSources.keys) {
                removeClient(client)
            }

            if listener >= 0 {
                Darwin.close(listener)
                listener = -1
            }
            try? FileManager.default.removeItem(at: socketURL)
        }
    }

    deinit {
        stop()
    }

    private func acceptAvailableClients() {
        while isRunning {
            let client = Darwin.accept(listener, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                return
            }

            var noSignal: Int32 = 1
            Darwin.setsockopt(
                client,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSignal,
                socklen_t(MemoryLayout.size(ofValue: noSignal))
            )
            do {
                try Self.makeNonBlocking(client)
                monitorClient(client)
                if let latestFrame {
                    send(latestFrame, toAll: [client])
                }
            } catch {
                Darwin.close(client)
            }
        }
    }

    private func send(_ data: Data, toAll descriptors: [Int32]) {
        for descriptor in descriptors {
            let wasSent = data.withUnsafeBytes { bytes -> Bool in
                guard let baseAddress = bytes.baseAddress else { return true }
                var offset = 0
                while offset < bytes.count {
                    let result = Darwin.send(
                        descriptor,
                        baseAddress.advanced(by: offset),
                        bytes.count - offset,
                        0
                    )
                    if result <= 0 {
                        return false
                    }
                    offset += result
                }
                return true
            }

            if !wasSent {
                removeClient(descriptor)
            }
        }
    }

    private func monitorClient(_ descriptor: Int32) {
        let clientSource = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: queue
        )
        clientSource.setEventHandler { [weak self] in
            self?.clientBecameReadable(descriptor)
        }
        clientSources[descriptor] = clientSource
        clientSource.resume()
    }

    private func clientBecameReadable(_ descriptor: Int32) {
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let count = Darwin.recv(
                descriptor,
                &buffer,
                buffer.count,
                0
            )
            if count > 0 {
                // The protocol is server-to-client only. Discard unexpected
                // client input so it cannot keep the read source spinning.
                continue
            }
            if count == 0 {
                removeClient(descriptor)
                return
            }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }
            removeClient(descriptor)
            return
        }
    }

    private func removeClient(_ descriptor: Int32) {
        guard let clientSource = clientSources.removeValue(forKey: descriptor) else {
            return
        }
        clientSource.setEventHandler {}
        clientSource.cancel()
        Darwin.close(descriptor)
    }

    private static func bind(descriptor: Int32, path: String) throws {
        let pathBytes = Array(path.utf8CString)
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= capacity else {
            throw UnixSocketStateServerError.pathTooLong(path)
        }

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
                Darwin.bind(descriptor, $0, addressLength)
            }
        }
        guard result == 0 else {
            throw UnixSocketStateServerError.systemCall("bind", errno)
        }
    }

    private static func makeNonBlocking(_ descriptor: Int32) throws {
        let flags = Darwin.fcntl(descriptor, F_GETFL)
        guard flags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
        else {
            throw UnixSocketStateServerError.systemCall("fcntl", errno)
        }
    }

    private static func canConnect(to path: String) -> Bool {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_un()
        let pathBytes = Array(path.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            return false
        }
        let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 2
        let addressLength = socklen_t(pathOffset + pathBytes.count)
        address.sun_len = UInt8(addressLength)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                _ = memcpy(destination, source.baseAddress, source.count)
            }
        }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, addressLength) == 0
            }
        }
    }
}
