import AppKit
import Foundation

public struct CodexRunningApplication: Sendable, Equatable {
    public static let bundleIdentifier = "com.openai.codex"

    public let processIdentifier: pid_t
    public let version: String?
    public let isFrontmost: Bool

    public init(processIdentifier: pid_t, version: String?, isFrontmost: Bool) {
        self.processIdentifier = processIdentifier
        self.version = version
        self.isFrontmost = isFrontmost
    }
}

@MainActor
public enum CodexApplicationLocator {
    public static func runningApplication() -> CodexRunningApplication? {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: CodexRunningApplication.bundleIdentifier)
            .first
        else {
            return nil
        }

        let version: String?
        if let bundleURL = application.bundleURL {
            let bundle = Bundle(url: bundleURL)
            version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        } else {
            version = nil
        }

        return CodexRunningApplication(
            processIdentifier: application.processIdentifier,
            version: version,
            isFrontmost: application.isActive
        )
    }
}
