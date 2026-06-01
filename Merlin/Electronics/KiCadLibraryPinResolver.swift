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

struct KiCadLocalLibraryCatalog: Codable, Sendable, Equatable {
    var generatedAt: Date
    var symbols: [KiCadSymbolDefinition]
    var footprints: [KiCadFootprintDefinition]
}

struct KiCadLibraryRoots: Codable, Sendable, Equatable {
    var generatedAt: Date
    var symbolRoot: URL
    var footprintRoot: URL
}

struct KiCadLibraryRootCache: Sendable {
    let fileName = "kicad-library-roots.json"

    func load(from directory: URL, maxAgeSeconds: Int, now: Date = Date()) throws -> KiCadLibraryRoots? {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let roots = try JSONDecoder().decode(KiCadLibraryRoots.self, from: Data(contentsOf: url))
        guard maxAgeSeconds <= 0 || now.timeIntervalSince(roots.generatedAt) <= Double(maxAgeSeconds) else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: roots.symbolRoot.path),
              FileManager.default.fileExists(atPath: roots.footprintRoot.path) else {
            return nil
        }
        return roots
    }

    func write(_ roots: KiCadLibraryRoots, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(roots).write(to: directory.appendingPathComponent(fileName))
    }
}

struct KiCadLibraryRootDiscovery: Sendable {
    func discover(searchRoots: [URL] = defaultSearchRoots()) -> KiCadLibraryRoots? {
        for root in searchRoots {
            for candidate in candidates(under: root) {
                let symbolRoot = candidate.appendingPathComponent("symbols", isDirectory: true)
                let footprintRoot = candidate.appendingPathComponent("footprints", isDirectory: true)
                if directoryExists(symbolRoot), directoryExists(footprintRoot) {
                    return KiCadLibraryRoots(generatedAt: Date(), symbolRoot: symbolRoot, footprintRoot: footprintRoot)
                }
            }
        }
        return nil
    }

    static func defaultSearchRoots() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications/KiCad"),
            URL(fileURLWithPath: "/Applications/KiCad/KiCad.app"),
            URL(fileURLWithPath: "/Library/Application Support/kicad"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/kicad", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/share/kicad"),
            URL(fileURLWithPath: "/usr/local/share/kicad"),
        ]
    }

    private func candidates(under root: URL) -> [URL] {
        [
            root,
            root.appendingPathComponent("share/kicad", isDirectory: true),
            root.appendingPathComponent("Contents/SharedSupport", isDirectory: true),
            root.appendingPathComponent("Contents/SharedSupport/kicad", isDirectory: true),
            root.appendingPathComponent("KiCad.app/Contents/SharedSupport", isDirectory: true),
            root.appendingPathComponent("KiCad.app/Contents/SharedSupport/kicad", isDirectory: true),
        ]
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

struct KiCadLibraryCatalogCache: Sendable {
    let fileName = "kicad-library-catalog.json"

    func load(from directory: URL, maxAgeSeconds: Int, now: Date = Date()) throws -> KiCadLocalLibraryCatalog? {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let catalog = try JSONDecoder().decode(KiCadLocalLibraryCatalog.self, from: Data(contentsOf: url))
        guard maxAgeSeconds <= 0 || now.timeIntervalSince(catalog.generatedAt) <= Double(maxAgeSeconds) else {
            return nil
        }
        return catalog
    }

    func write(_ catalog: KiCadLocalLibraryCatalog, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog).write(to: directory.appendingPathComponent(fileName))
    }
}

struct KiCadLibraryCatalogExtractor: Sendable {
    func extract(symbolRoot: URL?, footprintRoot: URL?) throws -> KiCadLocalLibraryCatalog {
        KiCadLocalLibraryCatalog(
            generatedAt: Date(),
            symbols: try symbolRoot.map(extractSymbols(from:)) ?? [],
            footprints: try footprintRoot.map(extractFootprints(from:)) ?? []
        )
    }

    func extractSymbols(from root: URL) throws -> [KiCadSymbolDefinition] {
        let files = try libraryFiles(under: root, extension: "kicad_sym")
        return try files.flatMap { file in
            let libraryName = file.deletingPathExtension().lastPathComponent
            let text = try String(contentsOf: file, encoding: .utf8)
            return symbolBlocks(in: text).compactMap { block -> KiCadSymbolDefinition? in
                guard let rawName = firstQuotedValue(after: "(symbol", in: block) else { return nil }
                let name = rawName.contains(":") ? rawName : "\(libraryName):\(rawName)"
                let pins = blocks(named: "pin", in: block).compactMap(parsePin)
                return KiCadSymbolDefinition(name: name, pins: pins)
            }
        }
        .sorted { $0.name < $1.name }
    }

    func extractFootprints(from root: URL) throws -> [KiCadFootprintDefinition] {
        let files = try libraryFiles(under: root, extension: "kicad_mod")
        return try files.compactMap { file -> KiCadFootprintDefinition? in
            let libraryName = footprintLibraryName(for: file)
            let text = try String(contentsOf: file, encoding: .utf8)
            let rawName = firstQuotedValue(after: "(footprint", in: text) ?? file.deletingPathExtension().lastPathComponent
            let name = libraryName.isEmpty || rawName.contains(":") ? rawName : "\(libraryName):\(rawName)"
            let pads = blocks(named: "pad", in: text).compactMap(parsePad)
            return KiCadFootprintDefinition(name: name, pads: pads)
        }
        .sorted { $0.name < $1.name }
    }

    private func libraryFiles(under root: URL, extension expectedExtension: String) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { entry in
            guard let url = entry as? URL,
                  url.pathExtension == expectedExtension else { return nil }
            return url
        }
        .sorted { $0.path < $1.path }
    }

    private func symbolBlocks(in text: String) -> [String] {
        blocks(named: "symbol", in: text).filter { block in
            firstQuotedValue(after: "(symbol", in: block) != nil
        }
    }

    private func parsePin(_ block: String) -> KiCadSymbolPin? {
        let electricalType = firstToken(after: "(pin", in: block) ?? "unspecified"
        guard let number = propertyValue("number", in: block) else { return nil }
        let name = propertyValue("name", in: block) ?? number
        return KiCadSymbolPin(number: number, name: name, electricalType: electricalType)
    }

    private func parsePad(_ block: String) -> KiCadFootprintPad? {
        guard let number = firstQuotedValue(after: "(pad", in: block) else { return nil }
        let name = propertyValue("pinfunction", in: block)
        return KiCadFootprintPad(number: number, name: name)
    }

    private func footprintLibraryName(for file: URL) -> String {
        let parent = file.deletingLastPathComponent().lastPathComponent
        guard parent.hasSuffix(".pretty") else { return "" }
        return String(parent.dropLast(".pretty".count))
    }

    private func propertyValue(_ property: String, in text: String) -> String? {
        firstQuotedValue(after: "(\(property)", in: text)
    }

    private func firstToken(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        let remainder = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.split { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == ")" }.first.map(String.init)
    }

    private func firstQuotedValue(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker),
              let firstQuote = text[range.upperBound...].firstIndex(of: "\"") else {
            return nil
        }
        let afterFirstQuote = text.index(after: firstQuote)
        guard let secondQuote = text[afterFirstQuote...].firstIndex(of: "\"") else { return nil }
        return String(text[afterFirstQuote..<secondQuote])
    }

    private func blocks(named name: String, in text: String) -> [String] {
        let marker = "(\(name)"
        var blocks: [String] = []
        var searchStart = text.startIndex
        while let markerRange = text.range(of: marker, range: searchStart..<text.endIndex) {
            guard let end = balancedBlockEnd(startingAt: markerRange.lowerBound, in: text) else {
                break
            }
            blocks.append(String(text[markerRange.lowerBound..<end]))
            searchStart = end
        }
        return blocks
    }

    private func balancedBlockEnd(startingAt start: String.Index, in text: String) -> String.Index? {
        var index = start
        var depth = 0
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return text.index(after: index)
                }
            }
            index = text.index(after: index)
        }
        return nil
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
