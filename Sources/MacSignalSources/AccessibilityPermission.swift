import ApplicationServices
import Foundation

public enum AccessibilityPermission {
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Only call this after a user presses a button. macOS remembers the request.
    @discardableResult
    public static func requestFromUser() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
