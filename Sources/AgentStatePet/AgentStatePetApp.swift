import AgentStateCore
import AgentStateRuntime
import AppKit
import ImageIO
import SwiftUI

@main
struct AgentStatePetApp: App {
    @StateObject private var model = PetViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        WindowGroup("桌宠") {
            PetView(model: model)
        }
        .defaultSize(width: 180, height: 180)
        .windowResizability(.contentSize)
    }
}

@MainActor
final class PetViewModel: ObservableObject {
    @Published private(set) var state: AgentActivityState = .unknown
    @Published private(set) var sequence: UInt64 = 0

    private let runtime = AgentStateRuntime()

    init() {
        runtime.onSnapshot = { [weak self] snapshot in
            self?.state = AgentActivityState(rawValue: snapshot.state) ?? .unknown
            self?.sequence = UInt64(clamping: snapshot.sequence)
        }
        runtime.onCodexTerminated = {
            NSApplication.shared.terminate(nil)
        }
        runtime.start()
        if let snapshot = runtime.currentSnapshot {
            state = AgentActivityState(rawValue: snapshot.state) ?? .unknown
            sequence = UInt64(clamping: snapshot.sequence)
        }
    }

}

private struct PetView: View {
    @ObservedObject var model: PetViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AnimatedGIFView(resourceName: model.state.animationResource)
                .frame(width: 180, height: 180)
                .accessibilityLabel("桌宠，当前状态：\(model.state.displayName)")

            Circle()
                .fill(model.state.indicatorColor)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                .shadow(radius: 2)
                .padding(8)
                .help(model.state.displayName)
        }
        .background(WindowConfigurator())
    }
}

private struct AnimatedGIFView: NSViewRepresentable {
    let resourceName: String

    func makeNSView(context: Context) -> GIFPlayerView {
        GIFPlayerView()
    }

    func updateNSView(_ nsView: GIFPlayerView, context: Context) {
        nsView.load(resourceName: resourceName)
    }
}

private final class GIFPlayerView: NSView {
    private static let displaySize = NSSize(width: 180, height: 180)

    private let imageView = NSImageView()
    private var loadedResource: String?
    private var frames: [NSImage] = []
    private var delays: [TimeInterval] = []
    private var frameIndex = 0
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let heading = NSMenuItem(
            title: "AgentStateBridge 桌宠",
            action: nil,
            keyEquivalent: ""
        )
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出桌宠",
            action: #selector(terminatePet),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func terminatePet() {
        NSApplication.shared.terminate(nil)
    }

    func load(resourceName: String) {
        guard loadedResource != resourceName else { return }
        loadedResource = resourceName
        timer?.invalidate()
        frames.removeAll(keepingCapacity: true)
        delays.removeAll(keepingCapacity: true)
        frameIndex = 0

        guard let url = petResourceURL(resourceName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else {
            imageView.image = nil
            return
        }

        let count = CGImageSourceGetCount(source)
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            frames.append(NSImage(cgImage: cgImage, size: Self.displaySize))
            delays.append(frameDelay(source: source, index: index))
        }

        imageView.image = frames.first
        scheduleNextFrame()
    }

    private func petResourceURL(_ resourceName: String) -> URL? {
        let resourceBundleName = "AgentStateBridge_AgentStatePet.bundle"
        if let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "gif",
            subdirectory: resourceBundleName
        ) {
            return url
        }

        // SwiftPM's development layout keeps the resource bundle beside the executable.
        return Bundle.module.url(forResource: resourceName, withExtension: "gif")
    }

    private func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let unclamped = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gifProperties?[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? 0.1
        return delay > 0.02 ? delay : 0.1
    }

    private func scheduleNextFrame() {
        guard frames.count > 1 else { return }
        let delay = delays[safe: frameIndex] ?? 0.1
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.advanceFrame()
            }
        }
    }

    private func advanceFrame() {
        guard !frames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % frames.count
        imageView.image = frames[frameIndex]
        scheduleNextFrame()
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfiguringView {
        WindowConfiguringView(frame: .zero)
    }

    func updateNSView(_ nsView: WindowConfiguringView, context: Context) {
        nsView.configureWindowIfNeeded()
    }
}

private final class WindowConfiguringView: NSView {
    private var hasPlacedInitialWindow = false
    private var placementScheduled = false
    private var placementAttemptCount = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowIfNeeded()
    }

    func configureWindowIfNeeded() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.setFrameAutosaveName("")

        // SwiftUI creates a titled window by default. Replacing its style mask
        // removes the traffic-light controls instead of merely hiding them.
        window.styleMask = [.borderless]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        scheduleInitialPlacement()
    }

    private func scheduleInitialPlacement() {
        guard !hasPlacedInitialWindow, !placementScheduled else {
            return
        }

        placementScheduled = true
        placementAttemptCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.placementScheduled = false
            if !self.placeWindowAtBottomRightIfNeeded(), self.placementAttemptCount < 10 {
                self.scheduleInitialPlacement()
            }
        }
    }

    @discardableResult
    private func placeWindowAtBottomRightIfNeeded() -> Bool {
        guard !hasPlacedInitialWindow,
              let window,
              window.isVisible,
              let screen = window.screen ?? NSScreen.main,
              window.frame.width > 1,
              window.frame.height > 1
        else {
            return false
        }

        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 24
        let origin = NSPoint(
            x: visibleFrame.maxX - window.frame.width - margin,
            y: visibleFrame.minY + margin
        )
        window.setFrameOrigin(origin)
        hasPlacedInitialWindow = true
        return true
    }
}

private extension AgentActivityState {
    var animationResource: String {
        switch self {
        case .idle: "06"
        case .composing: "05"
        case .reasoning: "04"
        case .working: "01"
        case .completed: "03"
        case .inactive: "02"
        // During normal launch, accessibility inspection briefly reports
        // unknown while Codex's accessibility tree becomes available.
        case .unknown: "06"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .inactive: .gray
        case .idle: .blue
        case .composing: .orange
        case .reasoning: .purple
        case .working: .green
        case .completed: .mint
        case .unknown: .secondary
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
