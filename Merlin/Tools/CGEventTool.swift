import CoreGraphics
import Foundation

enum CGEventToolError: Error, Sendable {
    case emptyKeyCombo
    case unknownKey(String)
    case eventCreationFailed
}

enum CGEventTool {
    private static let keyCodes: [String: CGKeyCode] = [
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
        "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
        "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
        "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
        "6": 22, "7": 26, "8": 28, "9": 25,
        "[": 33, "]": 30, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
        "`": 50, "-": 27, "=": 24, "\\": 42,
    ]

    private static let modifierFlags: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift, "opt": .maskAlternate,
        "option": .maskAlternate, "alt": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl,
    ]

    static func click(x: Double, y: Double, button: CGMouseButton = .left) throws {
        try postMouseSequence(at: CGPoint(x: x, y: y), button: button, clickCount: 1)
    }

    static func doubleClick(x: Double, y: Double) throws {
        try postMouseSequence(at: CGPoint(x: x, y: y), button: .left, clickCount: 2)
    }

    static func rightClick(x: Double, y: Double) throws {
        try postMouseSequence(at: CGPoint(x: x, y: y), button: .right, clickCount: 1)
    }

    static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double) throws {
        let from = CGPoint(x: fromX, y: fromY)
        let to = CGPoint(x: toX, y: toY)
        try postMouseEvent(type: .leftMouseDown, at: from, button: .left)
        try postMouseEvent(type: .leftMouseDragged, at: to, button: .left)
        try postMouseEvent(type: .leftMouseUp, at: to, button: .left)
    }

    static func typeText(_ text: String) throws {
        for character in text {
            let characters = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                throw CGEventToolError.eventCreationFailed
            }

            down.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
            up.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    static func pressKey(_ keyCombo: String) throws {
        let parsed = try parseKeyCombo(keyCombo)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: parsed.keyCode, keyDown: true) else {
            throw CGEventToolError.eventCreationFailed
        }
        event.flags = parsed.flags
        event.post(tap: .cghidEventTap)
    }

    static func scroll(x: Double, y: Double, deltaX: Double, deltaY: Double) throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY.rounded()),
            wheel2: Int32(deltaX.rounded()),
            wheel3: 0
        ) else {
            throw CGEventToolError.eventCreationFailed
        }
        event.post(tap: .cghidEventTap)
    }

    private static func postMouseSequence(at point: CGPoint, button: CGMouseButton, clickCount: Int) throws {
        try postMouseEvent(type: mouseDownType(for: button), at: point, button: button, clickCount: clickCount)
        try postMouseEvent(type: mouseUpType(for: button), at: point, button: button, clickCount: clickCount)
    }

    private static func postMouseEvent(type: CGEventType, at point: CGPoint, button: CGMouseButton, clickCount: Int = 1) throws {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
            throw CGEventToolError.eventCreationFailed
        }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.post(tap: .cghidEventTap)
    }

    private static func mouseDownType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .left: return .leftMouseDown
        case .right: return .rightMouseDown
        case .center: return .otherMouseDown
        @unknown default: return .leftMouseDown
        }
    }

    private static func mouseUpType(for button: CGMouseButton) -> CGEventType {
        switch button {
        case .left: return .leftMouseUp
        case .right: return .rightMouseUp
        case .center: return .otherMouseUp
        @unknown default: return .leftMouseUp
        }
    }

    private static func parseKeyCombo(_ keyCombo: String) throws -> (keyCode: CGKeyCode, flags: CGEventFlags) {
        let tokens = keyCombo
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }

        guard tokens.isEmpty == false else {
            throw CGEventToolError.emptyKeyCombo
        }

        var flags: CGEventFlags = []
        var keyToken: String?

        for token in tokens {
            if let modifier = modifierFlags[token] {
                flags.insert(modifier)
            } else if keyToken == nil {
                keyToken = token
            } else {
                throw CGEventToolError.unknownKey(token)
            }
        }

        guard let keyToken else {
            throw CGEventToolError.emptyKeyCombo
        }

        guard let keyCode = keyCodes[keyToken] else {
            throw CGEventToolError.unknownKey(keyToken)
        }

        return (keyCode, flags)
    }
}
