import AgentStateBridgeService
import AgentStateCore
import Foundation

@main
struct AgentStateExampleConsumer {
    static func main() {
        let arguments = CommandLine.arguments
        let shouldWatch = arguments.contains("--watch")
        let fileURL = customFileURL(arguments: arguments)
            ?? StateSnapshotWriter.defaultFileURL()
        let writer = StateSnapshotWriter(fileURL: fileURL)

        if shouldWatch {
            watch(writer: writer)
        } else {
            readOnce(writer: writer)
        }
    }

    private static func customFileURL(arguments: [String]) -> URL? {
        guard let fileIndex = arguments.firstIndex(of: "--file") else {
            return nil
        }
        let pathIndex = arguments.index(after: fileIndex)
        guard arguments.indices.contains(pathIndex) else {
            return nil
        }
        return URL(fileURLWithPath: arguments[pathIndex])
    }

    private static func readOnce(writer: StateSnapshotWriter) {
        do {
            printSnapshot(try writer.read())
        } catch {
            writeError("无法读取 \(writer.fileURL.path)：\(error.localizedDescription)")
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func watch(writer: StateSnapshotWriter) {
        var lastSequence: UInt64?
        var hasShownWaitingMessage = false

        while true {
            do {
                let snapshot = try writer.read()
                if snapshot.sequence != lastSequence {
                    printSnapshot(snapshot)
                    lastSequence = snapshot.sequence
                }
                hasShownWaitingMessage = false
            } catch {
                if !hasShownWaitingMessage {
                    writeError("等待状态文件：\(writer.fileURL.path)")
                    hasShownWaitingMessage = true
                }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private static func printSnapshot(_ snapshot: AgentStateEnvelope) {
        let percent = Int(snapshot.confidence * 100)
        let previous = snapshot.previousState?.rawValue ?? "-"
        print(
            "#\(snapshot.sequence) \(snapshot.state.rawValue) "
                + "confidence=\(percent)% previous=\(previous)"
        )
        fflush(stdout)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
