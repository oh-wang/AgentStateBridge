import AgentStateCore
import ApplicationServices
import Foundation

public enum AXTreeReadError: LocalizedError {
    case permissionMissing
    case cannotReadApplication(AXError)

    public var errorDescription: String? {
        switch self {
        case .permissionMissing:
            return "还没有获得“辅助功能”权限。"
        case let .cannotReadApplication(error):
            return "无法读取 Codex 的辅助功能界面（系统错误 \(error.rawValue)）。"
        }
    }
}

public protocol InspectionSnapshotReading: Sendable {
    func read(
        processIdentifier: pid_t,
        applicationVersion: String?,
        revealControlNames: Bool
    ) throws -> InspectionSnapshot
}

public struct AXTreeReader: InspectionSnapshotReading, Sendable {
    private struct ElementIdentity: Hashable {
        let element: AXUIElement

        static func == (lhs: ElementIdentity, rhs: ElementIdentity) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(element))
        }
    }

    public let maximumNodeCount: Int
    public let maximumDepth: Int

    public init(maximumNodeCount: Int = 5_000, maximumDepth: Int = 60) {
        self.maximumNodeCount = maximumNodeCount
        self.maximumDepth = maximumDepth
    }

    public func read(
        processIdentifier: pid_t,
        applicationVersion: String?,
        revealControlNames: Bool
    ) throws -> InspectionSnapshot {
        guard AccessibilityPermission.isGranted else {
            throw AXTreeReadError.permissionMissing
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        var roleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        guard result == .success else {
            throw AXTreeReadError.cannotReadApplication(result)
        }

        var nodes: [InspectedNode] = []
        var stack: [(element: AXUIElement, path: String, depth: Int)] = [
            (application, "0", 0)
        ]
        var visited: Set<ElementIdentity> = []
        var wasTruncated = false

        while let item = stack.popLast() {
            guard visited.insert(ElementIdentity(element: item.element)).inserted else {
                continue
            }

            if nodes.count >= maximumNodeCount {
                wasTruncated = true
                break
            }

            let children = axElements(item.element, attribute: kAXChildrenAttribute)
            nodes.append(
                makeNode(
                    element: item.element,
                    path: item.path,
                    depth: item.depth,
                    childCount: children.count,
                    revealControlNames: revealControlNames
                )
            )

            guard item.depth < maximumDepth else {
                if !children.isEmpty {
                    wasTruncated = true
                }
                continue
            }

            for (index, child) in children.enumerated().reversed() {
                stack.append((child, "\(item.path).\(index)", item.depth + 1))
            }
        }

        return InspectionSnapshot(
            capturedAt: Date(),
            applicationVersion: applicationVersion,
            processIdentifier: processIdentifier,
            nodes: nodes,
            wasTruncated: wasTruncated
        )
    }

    private func makeNode(
        element: AXUIElement,
        path: String,
        depth: Int,
        childCount: Int,
        revealControlNames: Bool
    ) -> InspectedNode {
        let role = stringAttribute(element, kAXRoleAttribute) ?? "未知控件"
        let rawTitle = stringAttribute(element, kAXTitleAttribute)
        let rawDescription = stringAttribute(element, kAXDescriptionAttribute)
        let rawHelp = stringAttribute(element, kAXHelpAttribute)
        let rawPlaceholder = stringAttribute(element, kAXPlaceholderValueAttribute)
        let rawValue = stringAttribute(element, kAXValueAttribute)
        let title = protectedTextAttribute(
            rawTitle,
            reveal: revealControlNames
        )
        let description = protectedTextAttribute(
            rawDescription,
            reveal: revealControlNames
        )
        let help = protectedTextAttribute(
            rawHelp,
            reveal: revealControlNames
        )

        return InspectedNode(
            id: path,
            depth: depth,
            role: role,
            subrole: stringAttribute(element, kAXSubroleAttribute),
            identifier: stringAttribute(element, kAXIdentifierAttribute),
            title: title,
            description: description,
            help: help,
            valueSummary: attribute(element, kAXValueAttribute)
                .map(PrivacyRedactor.summarizeValue),
            isEnabled: boolAttribute(element, kAXEnabledAttribute),
            isFocused: boolAttribute(element, kAXFocusedAttribute),
            childCount: childCount,
            semantic: ControlClassifier.semantic(
                role: role,
                title: rawTitle,
                description: rawDescription,
                help: rawHelp,
                value: rawValue
            ),
            hasUserText: ControlClassifier.hasUserText(
                role: role,
                value: rawValue,
                title: rawTitle,
                description: rawDescription,
                placeholder: rawPlaceholder
            ),
            ariaLive: stringAttribute(element, "AXARIALive")
        )
    }

    private func protectedTextAttribute(
        _ value: String?,
        reveal: Bool
    ) -> String? {
        guard let value else {
            return nil
        }
        guard !value.isEmpty else {
            return nil
        }
        return reveal ? value : PrivacyRedactor.summarize(value)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        (attribute(element, name) as? NSNumber)?.boolValue
    }

    private func axElements(_ element: AXUIElement, attribute name: String) -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }
}
