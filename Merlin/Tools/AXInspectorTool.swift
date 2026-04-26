import Accessibility
import AppKit
import Foundation

struct AXTree: Sendable {
    var elementCount: Int
    var isRich: Bool
    var elements: [AXElement]

    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(elements),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}

struct AXElement: Codable, Sendable {
    var role: String
    var label: String?
    var value: String?
    var frame: CGRect
    var children: [AXElement]
}

enum AXInspectorTool {
    private static let maxDepth = 8

    static func probe(bundleID: String) async -> AXTree {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return emptyTree
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let elements = collectElements(from: appElement, depth: 0)
        let elementCount = countElements(in: elements)
        let hasLabels = containsLabel(in: elements)
        return AXTree(
            elementCount: elementCount,
            isRich: elementCount > 10 && hasLabels,
            elements: elements
        )
    }

    static func findElement(bundleID: String, role: String?, label: String?, value: String?) async -> AXElement? {
        let tree = await probe(bundleID: bundleID)
        return findElement(in: tree.elements, role: role, label: label, value: value)
    }

    static func getElementValue(element: AXElement) async -> String? {
        element.value
    }

    private static var emptyTree: AXTree {
        AXTree(elementCount: 0, isRich: false, elements: [])
    }

    private static func collectElements(from element: AXUIElement, depth: Int) -> [AXElement] {
        guard depth < maxDepth else {
            return []
        }

        let children = copyChildren(from: element)
        return children.map { child in
            buildElement(from: child, depth: depth + 1)
        }
    }

    private static func buildElement(from element: AXUIElement, depth: Int) -> AXElement {
        AXElement(
            role: readStringAttribute(kAXRoleAttribute, from: element) ?? "unknown",
            label: readLabel(from: element),
            value: readValue(from: element),
            frame: readFrame(from: element),
            children: depth < maxDepth ? collectElements(from: element, depth: depth) : []
        )
    }

    private static func findElement(in elements: [AXElement], role: String?, label: String?, value: String?) -> AXElement? {
        for element in elements {
            if matches(element: element, role: role, label: label, value: value) {
                return element
            }

            if let found = findElement(in: element.children, role: role, label: label, value: value) {
                return found
            }
        }
        return nil
    }

    private static func matches(element: AXElement, role: String?, label: String?, value: String?) -> Bool {
        if let role, element.role != role { return false }
        if let label, element.label != label { return false }
        if let value, element.value != value { return false }
        return true
    }

    private static func countElements(in elements: [AXElement]) -> Int {
        elements.reduce(0) { partialResult, element in
            partialResult + 1 + countElements(in: element.children)
        }
    }

    private static func containsLabel(in elements: [AXElement]) -> Bool {
        for element in elements {
            if let label = element.label, label.isEmpty == false {
                return true
            }

            if containsLabel(in: element.children) {
                return true
            }
        }
        return false
    }

    private static func copyChildren(from element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(kAXChildrenAttribute, from: element) else {
            return []
        }

        if let array = value as? [Any] {
            return array.map { $0 as! AXUIElement }
        }

        return []
    }

    private static func readStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        guard let value = copyAttribute(attribute, from: element) else {
            return nil
        }

        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    private static func readLabel(from element: AXUIElement) -> String? {
        readStringAttribute(kAXTitleAttribute, from: element)
            ?? readStringAttribute(kAXDescriptionAttribute, from: element)
            ?? readStringAttribute(kAXHelpAttribute, from: element)
    }

    private static func readValue(from element: AXUIElement) -> String? {
        guard let value = copyAttribute(kAXValueAttribute, from: element) else {
            return nil
        }

        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return String(describing: value)
    }

    private static func readFrame(from element: AXUIElement) -> CGRect {
        guard let positionValue = copyAttribute(kAXPositionAttribute, from: element),
              let sizeValue = copyAttribute(kAXSizeAttribute, from: element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return .zero
        }

        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        guard AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetType(sizeAXValue) == .cgSize else {
            return .zero
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &origin),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return .zero
        }

        return CGRect(origin: origin, size: size)
    }

    private static func copyAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }
        return value
    }
}
