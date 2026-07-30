import ApplicationServices
import Foundation

public final class AXChangeMonitor {
    private final class CallbackBox {
        let handler: (String) -> Void

        init(handler: @escaping (String) -> Void) {
            self.handler = handler
        }
    }

    private var observer: AXObserver?
    private var callbackBox: CallbackBox?
    private let applicationElement: AXUIElement

    public init?(processIdentifier: pid_t, handler: @escaping (String) -> Void) {
        applicationElement = AXUIElementCreateApplication(processIdentifier)
        let box = CallbackBox(handler: handler)
        var newObserver: AXObserver?

        let result = AXObserverCreate(
            processIdentifier,
            { _, _, notification, context in
                guard let context else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
                box.handler(notification as String)
            },
            &newObserver
        )

        guard result == .success, let newObserver else {
            return nil
        }

        observer = newObserver
        callbackBox = box
        let context = Unmanaged.passUnretained(box).toOpaque()

        let notifications = [
            kAXFocusedUIElementChangedNotification,
            kAXValueChangedNotification,
            "AXCreated",
            "AXLiveRegionCreated",
            "AXLiveRegionChanged",
            kAXUIElementDestroyedNotification,
            kAXWindowCreatedNotification,
            kAXTitleChangedNotification,
            kAXLayoutChangedNotification
        ]

        for notification in notifications {
            AXObserverAddNotification(
                newObserver,
                applicationElement,
                notification as CFString,
                context
            )
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
    }

    deinit {
        stop()
    }

    public func stop() {
        guard let observer else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        self.observer = nil
        callbackBox = nil
    }
}
