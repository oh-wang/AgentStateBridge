import AppKit
import Foundation

public struct ChatGPTRunningApplication: Sendable, Equatable {
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
public enum ChatGPTApplicationLocator {
    public static func runningApplication() -> ChatGPTRunningApplication? {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: ChatGPTRunningApplication.bundleIdentifier)
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

        return ChatGPTRunningApplication(
            processIdentifier: application.processIdentifier,
            version: version,
            isFrontmost: application.isActive
        )
    }
}
