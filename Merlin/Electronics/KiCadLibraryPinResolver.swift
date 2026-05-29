import Foundation

struct KiCadSymbolPin: Codable, Sendable, Equatable, Hashable {
    var number: String
    var name: String
    var electricalType: String
}

struct KiCadSymbolDefinition: Codable, Sendable, Equatable {
    var name: String
    var pins: [KiCadSymbolPin]

    var symbolName: String {
        name
    }
}

struct KiCadFootprintPad: Codable, Sendable, Equatable, Hashable {
    var number: String
    var name: String?
}

struct KiCadFootprintDefinition: Codable, Sendable, Equatable {
    var name: String
    var pads: [KiCadFootprintPad]

    var footprintName: String {
        name
    }
}

struct KiCadLibraryResolutionIssue: Codable, Sendable, Equatable {
    var code: String
    var message: String
    var affectedRef: String
}

struct KiCadLibraryPinResolution: Codable, Sendable, Equatable {
    var componentRefdes: String
    var symbolEvidence: KiCadSymbolDefinition?
    var footprintEvidence: KiCadFootprintDefinition?
    var pinPadMap: [String: String]
    var issues: [KiCadLibraryResolutionIssue]

    var isResolved: Bool {
        issues.isEmpty
    }

    func contains(code: String) -> Bool {
        issues.contains { $0.code == code }
    }
}

struct KiCadLibraryPinResolver: Sendable {
    private let symbolsByName: [String: KiCadSymbolDefinition]
    private let footprintsByName: [String: KiCadFootprintDefinition]

    init(symbols: [KiCadSymbolDefinition], footprints: [KiCadFootprintDefinition]) {
        self.symbolsByName = Dictionary(symbols.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.footprintsByName = Dictionary(footprints.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func resolve(component: CircuitComponent, pcbBound: Bool) -> KiCadLibraryPinResolution {
        var issues: [KiCadLibraryResolutionIssue] = []
        let symbol = symbolsByName[component.selectedSymbol]
        let footprint = component.selectedFootprint.flatMap { footprintsByName[$0] }
        var pinPadMap: [String: String] = [:]

        if symbol == nil {
            issues.append(issue("UNKNOWN_SYMBOL", "\(component.selectedSymbol) is not in the symbol library.", component.refdes))
        }
        if pcbBound, component.manufacturerPartNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            issues.append(issue("MPN_MISSING", "\(component.refdes) has no manufacturer part number evidence.", component.refdes))
        }
        if pcbBound, component.selectedFootprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            issues.append(issue("PACKAGE_UNRESOLVED", "\(component.refdes) has no resolved footprint/package.", component.refdes))
        } else if pcbBound, footprint == nil {
            issues.append(issue("UNKNOWN_FOOTPRINT", "\(component.selectedFootprint ?? "") is not in the footprint library.", component.refdes))
        }

        if let symbol {
            let symbolPinsByName = Dictionary(uniqueKeysWithValues: symbol.pins.map { ($0.name, $0) })
            for pin in component.pins {
                guard let libraryPin = symbolPinsByName[pin.symbolPin] else {
                    issues.append(issue("PIN_MISMATCH", "\(pin.symbolPin) is not present on \(symbol.name).", component.refdes))
                    continue
                }
                if libraryPin.number != pin.pinNumber {
                    issues.append(issue("PIN_MISMATCH", "\(pin.symbolPin) pin number does not match \(symbol.name).", component.refdes))
                }
            }
        }

        if let footprint {
            let padsByNumber = Dictionary(uniqueKeysWithValues: footprint.pads.map { ($0.number, $0) })
            for pin in component.pins {
                guard let padNumber = pin.footprintPad,
                      let pad = padsByNumber[padNumber] else {
                    issues.append(issue("PIN_MISMATCH", "\(pin.symbolPin) does not map to a valid footprint pad.", component.refdes))
                    continue
                }
                if let padName = pad.name, !padName.isEmpty, padName != pin.symbolPin {
                    issues.append(issue("PIN_MISMATCH", "\(pin.symbolPin) maps to incompatible pad \(pad.number).", component.refdes))
                } else {
                    pinPadMap[pin.symbolPin] = pad.number
                }
            }
        }

        return KiCadLibraryPinResolution(
            componentRefdes: component.refdes,
            symbolEvidence: symbol,
            footprintEvidence: footprint,
            pinPadMap: pinPadMap,
            issues: issues
        )
    }

    private func issue(_ code: String, _ message: String, _ affectedRef: String) -> KiCadLibraryResolutionIssue {
        KiCadLibraryResolutionIssue(code: code, message: message, affectedRef: affectedRef)
    }
}
