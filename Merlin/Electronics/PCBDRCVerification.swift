import Foundation

struct BoardOutline: Codable, Sendable, Equatable {
    var widthMm: Double
    var heightMm: Double
}

struct PCBFootprintAssignment: Codable, Sendable, Equatable {
    var componentRefdes: String
    var footprintName: String
    var pinPadMap: [String: String]
}

struct PCBBoardCandidate: Codable, Sendable, Equatable {
    var boardProfile: BoardProfile
    var outline: BoardOutline
    var footprintAssignments: [PCBFootprintAssignment]
    var netClassPlan: NetClassPlan
    var placementPlan: PlacementPlan
}

struct PCBBoardPlanner: Sendable {
    func buildCandidate(
        circuitIR: CircuitIR,
        boardProfile: BoardProfile,
        outline: BoardOutline,
        footprintResolutions: [KiCadLibraryPinResolution]
    ) -> PCBBoardCandidate {
        let assignments = footprintResolutions.compactMap { resolution -> PCBFootprintAssignment? in
            guard let footprint = resolution.footprintEvidence else { return nil }
            return PCBFootprintAssignment(
                componentRefdes: resolution.componentRefdes,
                footprintName: footprint.name,
                pinPadMap: resolution.pinPadMap
            )
        }

        var classes: [String: [String: Double]] = [:]
        for net in circuitIR.nets {
            classes[net.netClass] = [
                "min_trace_mm": boardProfile.minTraceMm,
                "clearance_mm": boardProfile.minClearanceMm,
            ]
        }
        for constraint in circuitIR.constraints where constraint.kind == "clearance" {
            let numeric = constraint.value.replacingOccurrences(of: "mm", with: "")
            if let value = Double(numeric) {
                classes[constraint.target, default: [:]]["clearance_mm"] = value
            }
        }

        let placementHints = Dictionary(
            uniqueKeysWithValues: circuitIR.constraints
                .filter { $0.kind == "placement" }
                .map { ($0.target, $0.value) }
        )

        return PCBBoardCandidate(
            boardProfile: boardProfile,
            outline: outline,
            footprintAssignments: assignments,
            netClassPlan: NetClassPlan(designId: circuitIR.designId, classes: classes),
            placementPlan: PlacementPlan(
                designId: circuitIR.designId,
                hints: placementHints,
                keepouts: circuitIR.constraints.filter { $0.kind == "keepout" }.map(\.value)
            )
        )
    }
}

struct CircuitIRKiCadBoardMaterialization: Sendable, Equatable {
    var boardURL: URL
}

enum CircuitIRKiCadBoardMaterializerError: Error, Equatable {
    case invalidBoardEvidence([ElectronicsSchemaIssue])
}

struct CircuitIRKiCadBoardMaterializer: Sendable {
    var footprintRoot: URL?

    init(footprintRoot: URL? = nil) {
        self.footprintRoot = footprintRoot
    }

    func materialize(
        circuitIR: CircuitIR,
        outputDirectory: URL
    ) throws -> CircuitIRKiCadBoardMaterialization {
        let validation = validate(circuitIR: circuitIR)
        guard validation.isValid else {
            throw CircuitIRKiCadBoardMaterializerError.invalidBoardEvidence(validation.issues)
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let boardURL = outputDirectory.appendingPathComponent("\(circuitIR.boardId).kicad_pcb")
        try boardText(circuitIR: circuitIR).write(to: boardURL, atomically: true, encoding: .utf8)
        return CircuitIRKiCadBoardMaterialization(boardURL: boardURL)
    }

    func validate(circuitIR: CircuitIR) -> ElectronicsSchemaValidationResult {
        var issues: [ElectronicsSchemaIssue] = []
        for component in circuitIR.components {
            if component.selectedFootprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                issues.append(issue("PCB_FOOTPRINT_REQUIRED", "\(component.refdes) has no selected footprint."))
            }
            if component.pins.isEmpty {
                issues.append(issue("PCB_PINS_REQUIRED", "\(component.refdes) has no pin evidence."))
            }
            for pin in component.pins where pin.footprintPad?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                issues.append(issue("PCB_PIN_PAD_REQUIRED", "\(component.refdes).\(pin.pinNumber) has no footprint pad evidence."))
            }
        }
        var netNamesByEndpoint: [String: Set<String>] = [:]
        for net in circuitIR.nets {
            for endpoint in net.endpoints {
                netNamesByEndpoint["\(endpoint.componentRefdes).\(endpoint.pinNumber)", default: []].insert(net.name)
            }
        }
        for (endpoint, netNames) in netNamesByEndpoint where netNames.count > 1 {
            issues.append(issue(
                "PCB_ENDPOINT_NET_CONFLICT",
                "\(endpoint) is assigned to multiple nets: \(netNames.sorted().joined(separator: ", "))."
            ))
        }
        return ElectronicsSchemaValidationResult(issues: issues)
    }

    private func boardText(circuitIR: CircuitIR) -> String {
        let layout = placementLayout(for: circuitIR)
        let routeCorridorWidth = max(
            24.0,
            Double(circuitIR.nets.filter { $0.endpoints.count > 1 }.count) * 2.0 + 16.0
        )
        let outline = BoardOutline(
            widthMm: layout.outline.widthMm + routeCorridorWidth,
            heightMm: layout.outline.heightMm
        )
        let netIDs = netIDsByName(circuitIR: circuitIR)
        let pinNetNames = netNamesByEndpoint(circuitIR: circuitIR)
        let nets = netIDs
            .sorted { $0.value < $1.value }
            .map { #"  (net \#($0.value) "\#(escaped($0.key))")"# }
            .joined(separator: "\n")
        let footprints = layout.placements.map { placed in
            footprintNode(
                component: placed.component,
                at: placed.at,
                netIDs: netIDs,
                pinNetNames: pinNetNames
            )
        }
            .joined(separator: "\n")
        let routes = routeSegments(
            circuitIR: circuitIR,
            layout: layout,
            outline: outline,
            netIDs: netIDs
        )
            .joined(separator: "\n")

        return """
        (kicad_pcb
          (version 20250114)
          (generator "merlin-electronics")
          (general (thickness 1.6))
          (paper "A4")
          (layers
            (0 "F.Cu" signal)
            (31 "B.Cu" signal)
            (32 "B.Adhes" user "B.Adhesive")
            (33 "F.Adhes" user "F.Adhesive")
            (34 "B.Paste" user)
            (35 "F.Paste" user)
            (36 "B.SilkS" user "B.Silkscreen")
            (37 "F.SilkS" user "F.Silkscreen")
            (38 "B.Mask" user)
            (39 "F.Mask" user)
            (40 "Dwgs.User" user "User.Drawings")
            (41 "Cmts.User" user "User.Comments")
            (42 "Eco1.User" user "User.Eco1")
            (43 "Eco2.User" user "User.Eco2")
            (44 "Edge.Cuts" user)
            (45 "Margin" user)
            (46 "B.CrtYd" user "B.Courtyard")
            (47 "F.CrtYd" user)
            (48 "B.Fab" user)
            (49 "F.Fab" user)
          )
          (setup
            (pad_to_mask_clearance 0)
            (allow_soldermask_bridges_in_footprints no)
            (pcbplotparams)
          )
          (net 0 "")
        \(nets)
          (gr_rect
            (start 0 0)
            (end \(number(outline.widthMm)) \(number(outline.heightMm)))
            (stroke (width 0.1) (type default))
            (fill no)
            (layer "Edge.Cuts")
            (uuid "\(stableUUID("outline", circuitIR.designId, circuitIR.boardId))")
          )
        \(footprints)
        \(routes)
        )
        """
    }

    private func footprintNode(
        component: CircuitComponent,
        at: KiCadSchematicDocument.Point,
        netIDs: [String: Int],
        pinNetNames: [String: String]
    ) -> String {
        let footprint = component.selectedFootprint ?? "Merlin:Unresolved"
        let value = escaped(component.constraints["value"] ?? component.manufacturerPartNumber ?? component.role)
        if let imported = importedFootprintNode(
            component: component,
            footprint: footprint,
            value: value,
            at: at,
            netIDs: netIDs,
            pinNetNames: pinNetNames
        ) {
            return imported
        }

        let escapedFootprint = escaped(footprint)
        let pads = component.pins.enumerated().map { padIndex, pin in
            padNode(
                component: component,
                pin: pin,
                padIndex: padIndex,
                netIDs: netIDs,
                pinNetNames: pinNetNames
            )
        }
            .joined(separator: "\n")

        return """
          (footprint "\(escapedFootprint)"
            (layer "F.Cu")
            (uuid "\(stableUUID("footprint", component.refdes))")
            (at \(number(at.x)) \(number(at.y)) 0)
            (property "Reference" "\(escaped(component.refdes))" (at 0 -2 0) (layer "F.SilkS") (uuid "\(stableUUID("property", component.refdes, "reference"))")
              (effects (font (size 1 1) (thickness 0.15))))
            (property "Value" "\(value)" (at 0 2 0) (layer "F.Fab") (uuid "\(stableUUID("property", component.refdes, "value"))")
              (effects (font (size 1 1) (thickness 0.15))))
            (property "Footprint" "\(escapedFootprint)" (at 0 3.5 0) (layer "F.Fab") hide (uuid "\(stableUUID("property", component.refdes, "footprint"))")
              (effects (font (size 1 1) (thickness 0.15))))
            (fp_text reference "\(escaped(component.refdes))" (at 0 -2 0) (layer "F.SilkS")
              (effects (font (size 1 1) (thickness 0.15))))
            (fp_text value "\(value)" (at 0 2 0) (layer "F.Fab")
              (effects (font (size 1 1) (thickness 0.15))))
            (attr through_hole)
        \(pads)
          )
        """
    }

    private func importedFootprintNode(
        component: CircuitComponent,
        footprint: String,
        value: String,
        at: KiCadSchematicDocument.Point,
        netIDs: [String: Int],
        pinNetNames: [String: String]
    ) -> String? {
        guard let sourceURL = footprintSourceURL(for: footprint),
              var text = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            return nil
        }
        text = rewriteFootprintHeader(text, fullName: footprint)
        text = ensureFootprintPlacement(text, component: component, at: at)
        text = rewriteFootprintProperty(text, name: "Reference", value: component.refdes)
        text = rewriteFootprintProperty(text, name: "Value", value: value)
        text = rewriteFootprintText(text, kind: "reference", value: component.refdes)
        text = rewriteFootprintText(text, kind: "value", value: value)
        text = rewriteFootprintPadNets(text, component: component, netIDs: netIDs, pinNetNames: pinNetNames)
        text = rewriteUUIDs(text, component: component)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "  \($0)" }
            .joined(separator: "\n")
    }

    private func footprintSourceURL(for footprint: String) -> URL? {
        guard let footprintRoot,
              let separator = footprint.firstIndex(of: ":") else {
            return nil
        }
        let library = String(footprint[..<separator])
        let name = String(footprint[footprint.index(after: separator)...])
        let url = footprintRoot
            .appendingPathComponent("\(library).pretty", isDirectory: true)
            .appendingPathComponent("\(name).kicad_mod")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func rewriteFootprintHeader(_ text: String, fullName: String) -> String {
        guard let firstQuote = text.firstIndex(of: "\""),
              let secondQuote = text[text.index(after: firstQuote)...].firstIndex(of: "\"") else {
            return text
        }
        var result = text
        result.replaceSubrange(text.index(after: firstQuote)..<secondQuote, with: escaped(fullName))
        return result
    }

    private struct FootprintBounds {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double

        var width: Double { max(maxX - minX, 1) }
        var height: Double { max(maxY - minY, 1) }
        var midX: Double { (minX + maxX) / 2 }
        var midY: Double { (minY + maxY) / 2 }

        static func fallback(pinCount: Int) -> FootprintBounds {
            let width = max(8, Double(max(pinCount, 1)) * 2.54 + 4)
            return FootprintBounds(minX: -2, minY: -4, maxX: width, maxY: 4)
        }

        mutating func include(x: Double, y: Double) {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }

        func translated(by point: KiCadSchematicDocument.Point) -> FootprintBounds {
            FootprintBounds(
                minX: minX + point.x,
                minY: minY + point.y,
                maxX: maxX + point.x,
                maxY: maxY + point.y
            )
        }
    }

    private struct FootprintGeometry {
        var bounds: FootprintBounds
        var padCenters: [String: [KiCadSchematicDocument.Point]]
    }

    private struct PlacedFootprint {
        var component: CircuitComponent
        var at: KiCadSchematicDocument.Point
        var geometry: FootprintGeometry
    }

    private struct FootprintPlacementLayout {
        var outline: BoardOutline
        var placements: [PlacedFootprint]
    }

    private struct RoutedBoardPoint {
        var componentRefdes: String
        var point: KiCadSchematicDocument.Point
        var bounds: FootprintBounds
        var componentPadCenters: [KiCadSchematicDocument.Point]
    }

    private func placementLayout(for circuitIR: CircuitIR) -> FootprintPlacementLayout {
        let components = connectivityOrderedComponents(circuitIR: circuitIR)
        let geometries = components.map(footprintGeometry(for:))
        let margin = 12.0
        let spacingX = 18.0
        let spacingY = 36.0
        let targetWidth = max(180.0, min(380.0, sqrt(geometries.reduce(0.0) { $0 + $1.bounds.width * $1.bounds.height }) * 2.2))

        var placements: [PlacedFootprint] = []
        var cursorY = margin
        var usedWidth = 0.0

        for (component, geometry) in zip(components, geometries) {
            let bounds = geometry.bounds
            let at = KiCadSchematicDocument.Point(
                x: margin - bounds.minX,
                y: cursorY - bounds.minY
            )
            placements.append(PlacedFootprint(component: component, at: at, geometry: geometry))
            usedWidth = max(usedWidth, margin + bounds.width + spacingX)
            cursorY += bounds.height + spacingY
        }

        return FootprintPlacementLayout(
            outline: BoardOutline(
                widthMm: max(targetWidth, usedWidth + margin),
                heightMm: max(80, cursorY + margin)
            ),
            placements: placements
        )
    }

    private func connectivityOrderedComponents(circuitIR: CircuitIR) -> [CircuitComponent] {
        let originalIndex = Dictionary(uniqueKeysWithValues: circuitIR.components.enumerated().map { ($0.element.refdes, $0.offset) })
        let componentsByRefdes = Dictionary(uniqueKeysWithValues: circuitIR.components.map { ($0.refdes, $0) })
        var neighbors: [String: Set<String>] = Dictionary(uniqueKeysWithValues: circuitIR.components.map { ($0.refdes, []) })
        for net in circuitIR.nets {
            let refdes = Array(Set(net.endpoints.map(\.componentRefdes))).sorted { (originalIndex[$0] ?? .max) < (originalIndex[$1] ?? .max) }
            guard refdes.count > 1 else { continue }
            for pair in zip(refdes, refdes.dropFirst()) {
                neighbors[pair.0, default: []].insert(pair.1)
                neighbors[pair.1, default: []].insert(pair.0)
            }
        }

        var unassigned = Set(circuitIR.components.map(\.refdes))
        var groups: [[String]] = []
        while let start = unassigned.min(by: { (originalIndex[$0] ?? .max) < (originalIndex[$1] ?? .max) }) {
            var stack = [start]
            var group: [String] = []
            unassigned.remove(start)
            while let refdes = stack.popLast() {
                group.append(refdes)
                let next = (neighbors[refdes] ?? [])
                    .filter { unassigned.contains($0) }
                    .sorted { (originalIndex[$0] ?? .max) > (originalIndex[$1] ?? .max) }
                for neighbor in next {
                    unassigned.remove(neighbor)
                    stack.append(neighbor)
                }
            }
            groups.append(group)
        }

        return groups
            .sorted { groupA, groupB in
                let indexA = groupA.compactMap { originalIndex[$0] }.min() ?? .max
                let indexB = groupB.compactMap { originalIndex[$0] }.min() ?? .max
                return indexA < indexB
            }
            .flatMap { orderedConnectivityPath(refdes: $0, neighbors: neighbors, originalIndex: originalIndex) }
            .compactMap { componentsByRefdes[$0] }
    }

    private func orderedConnectivityPath(
        refdes group: [String],
        neighbors: [String: Set<String>],
        originalIndex: [String: Int]
    ) -> [String] {
        let groupSet = Set(group)
        let start = group
            .filter { (neighbors[$0] ?? []).filter { groupSet.contains($0) }.count <= 1 }
            .min { (originalIndex[$0] ?? .max) < (originalIndex[$1] ?? .max) }
            ?? group.min { (originalIndex[$0] ?? .max) < (originalIndex[$1] ?? .max) }
            ?? group[0]
        var visited: Set<String> = []
        var result: [String] = []

        func walk(_ refdes: String) {
            visited.insert(refdes)
            result.append(refdes)
            let next = (neighbors[refdes] ?? [])
                .filter { groupSet.contains($0) && !visited.contains($0) }
                .sorted { (originalIndex[$0] ?? .max) < (originalIndex[$1] ?? .max) }
            for neighbor in next {
                walk(neighbor)
            }
        }

        walk(start)
        for refdes in group.sorted(by: { (originalIndex[$0] ?? .max) < (originalIndex[$1] ?? .max) }) where !visited.contains(refdes) {
            walk(refdes)
        }
        return result
    }

    private func footprintGeometry(for component: CircuitComponent) -> FootprintGeometry {
        guard let footprint = component.selectedFootprint,
              let sourceURL = footprintSourceURL(for: footprint),
              let text = try? String(contentsOf: sourceURL, encoding: .utf8),
              let geometry = footprintGeometry(from: text) else {
            return FootprintGeometry(
                bounds: .fallback(pinCount: component.pins.count),
                padCenters: Dictionary(uniqueKeysWithValues: component.pins.enumerated().map { index, pin in
                    (pin.footprintPad ?? pin.pinNumber, [KiCadSchematicDocument.Point(x: Double(index) * 2.54, y: 0)])
                })
            )
        }
        return geometry
    }

    private func footprintGeometry(from text: String) -> FootprintGeometry? {
        var bounds: FootprintBounds?
        var padCenters: [String: [KiCadSchematicDocument.Point]] = [:]
        func include(_ x: Double, _ y: Double) {
            if bounds == nil {
                bounds = FootprintBounds(minX: x, minY: y, maxX: x, maxY: y)
            } else {
                bounds?.include(x: x, y: y)
            }
        }

        for match in regexMatches(#"\((?:start|end|xy)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\)"#, in: text) {
            guard match.count == 3,
                  let x = Double(match[1]),
                  let y = Double(match[2]) else { continue }
            include(x, y)
        }

        var searchIndex = text.startIndex
        while let padStart = text[searchIndex...].range(of: "(pad ")?.lowerBound,
              let padEnd = balancedNodeEnd(in: text, start: padStart) {
            let padBlock = String(text[padStart..<padEnd])
            let padName = firstQuotedValue(in: padBlock)
            if let at = firstPair(pattern: #"\(at\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)"#, in: padBlock),
                let size = firstPair(pattern: #"\(size\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)"#, in: padBlock) {
                if let padName {
                    padCenters[padName, default: []].append(KiCadSchematicDocument.Point(x: at.x, y: at.y))
                }
                include(at.x - size.x / 2, at.y - size.y / 2)
                include(at.x + size.x / 2, at.y + size.y / 2)
            }
            searchIndex = padEnd
        }

        guard let bounds else { return nil }
        return FootprintGeometry(bounds: bounds, padCenters: padCenters)
    }

    private func routeSegments(
        circuitIR: CircuitIR,
        layout: FootprintPlacementLayout,
        outline: BoardOutline,
        netIDs: [String: Int]
    ) -> [String] {
        let padCenters = absolutePadCenters(layout: layout)
        let footprintBounds = absoluteFootprintBounds(layout: layout)
        let componentPadCenters = absoluteComponentPadCenters(layout: layout)
        var segments: [String] = []
        let routedNets = circuitIR.nets.filter { net in
            net.endpoints.flatMap { endpoint in
                padCenters["\(endpoint.componentRefdes)|\(endpoint.pinNumber)"] ?? []
            }.count > 1
        }

        for (routeIndex, net) in routedNets.enumerated() {
            guard let netID = netIDs[net.name], netID > 0 else { continue }
            let points = uniqueRoutedPoints(net.endpoints.flatMap { endpoint -> [RoutedBoardPoint] in
                let key = "\(endpoint.componentRefdes)|\(endpoint.pinNumber)"
                guard let centers = padCenters[key],
                      let bounds = footprintBounds[endpoint.componentRefdes] else {
                    return []
                }
                return centers.map {
                    RoutedBoardPoint(
                        componentRefdes: endpoint.componentRefdes,
                        point: $0,
                        bounds: bounds,
                        componentPadCenters: componentPadCenters[endpoint.componentRefdes] ?? []
                    )
                }
            })
                .sorted { lhs, rhs in
                    if lhs.point.y == rhs.point.y { return lhs.point.x < rhs.point.x }
                    return lhs.point.y < rhs.point.y
                }
            guard points.count > 1 else { continue }

            for (pointIndex, pair) in zip(points, points.dropFirst()).enumerated() {
                segments.append(contentsOf: connectionSegments(
                    from: pair.0,
                    to: pair.1,
                    netID: netID,
                    netName: net.name,
                    routeIndex: routeIndex,
                    pointIndex: pointIndex,
                    outline: outline
                ))
            }
        }
        return segments.filter { !$0.isEmpty }
    }

    private func connectionSegments(
        from source: RoutedBoardPoint,
        to destination: RoutedBoardPoint,
        netID: Int,
        netName: String,
        routeIndex: Int,
        pointIndex: Int,
        outline: BoardOutline
    ) -> [String] {
        let layer = netID.isMultiple(of: 2) ? "F.Cu" : "B.Cu"
        if source.point.x == destination.point.x || source.point.y == destination.point.y {
            return [
                segmentNode(
                    start: source.point,
                    end: destination.point,
                    netID: netID,
                    layer: layer,
                    discriminator: "\(netName)-\(pointIndex)-direct"
                ),
            ]
        }

        let laneY = routingLaneY(
            from: source.bounds,
            to: destination.bounds,
            routeIndex: routeIndex,
            outline: outline
        )
        let sourceEscape = endpointEscapePoint(for: source, laneY: laneY, outline: outline)
        let destinationEscape = endpointEscapePoint(for: destination, laneY: laneY, outline: outline)
        let sourceCorner = KiCadSchematicDocument.Point(x: sourceEscape.x, y: laneY)
        let destinationCorner = KiCadSchematicDocument.Point(x: destinationEscape.x, y: laneY)
        return [
            segmentNode(
                start: source.point,
                end: sourceEscape,
                netID: netID,
                layer: layer,
                discriminator: "\(netName)-\(pointIndex)-source-footprint-escape"
            ),
            segmentNode(
                start: sourceEscape,
                end: sourceCorner,
                netID: netID,
                layer: layer,
                discriminator: "\(netName)-\(pointIndex)-source-lane-escape"
            ),
            segmentNode(
                start: sourceCorner,
                end: destinationCorner,
                netID: netID,
                layer: layer,
                discriminator: "\(netName)-\(pointIndex)-lane"
            ),
            segmentNode(
                start: destinationCorner,
                end: destinationEscape,
                netID: netID,
                layer: layer,
                discriminator: "\(netName)-\(pointIndex)-destination-lane-escape"
            ),
            segmentNode(
                start: destinationEscape,
                end: destination.point,
                netID: netID,
                layer: layer,
                discriminator: "\(netName)-\(pointIndex)-destination-footprint-escape"
            ),
        ]
    }

    private func endpointEscapePoint(
        for routedPoint: RoutedBoardPoint,
        laneY: Double,
        outline: BoardOutline
    ) -> KiCadSchematicDocument.Point {
        let columnPads = routedPoint.componentPadCenters.filter { abs($0.x - routedPoint.point.x) < 0.25 }
        let rowPads = routedPoint.componentPadCenters.filter { abs($0.y - routedPoint.point.y) < 0.25 }
        if columnPads.count > rowPads.count {
            return KiCadSchematicDocument.Point(
                x: escapeX(for: routedPoint.point, bounds: routedPoint.bounds),
                y: routedPoint.point.y
            )
        }
        return KiCadSchematicDocument.Point(
            x: routedPoint.point.x,
            y: escapeY(
                for: routedPoint.point,
                bounds: routedPoint.bounds,
                componentPadCenters: routedPoint.componentPadCenters,
                laneOffset: min(max(abs(laneY - routedPoint.point.y), 2.0), 8.0),
                outline: outline
            )
        )
    }

    private func escapeX(for point: KiCadSchematicDocument.Point, bounds: FootprintBounds) -> Double {
        if point.x <= bounds.midX {
            return bounds.minX - 2.0
        }
        return bounds.maxX + 2.0
    }

    private func routingLaneY(
        from source: FootprintBounds,
        to destination: FootprintBounds,
        routeIndex: Int,
        outline: BoardOutline
    ) -> Double {
        let upper = source.midY <= destination.midY ? source : destination
        let lower = source.midY <= destination.midY ? destination : source
        let gap = lower.minY - upper.maxY
        if gap > 6.0 {
            let offset = 2.0 + Double(routeIndex % 12) * 0.75
            return min(upper.maxY + offset, lower.minY - 2.0)
        }
        let below = max(source.maxY, destination.maxY) + 2.0 + Double(routeIndex % 12) * 0.75
        return min(max(below, 2.0), outline.heightMm - 2.0)
    }

    private func uniqueRoutedPoints(_ points: [RoutedBoardPoint]) -> [RoutedBoardPoint] {
        var seen: Set<String> = []
        var result: [RoutedBoardPoint] = []
        for point in points {
            let key = pointKey(point.point)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(point)
        }
        return result
    }

    private func pointKey(_ point: KiCadSchematicDocument.Point) -> String {
        "\(number(point.x))|\(number(point.y))"
    }

    private func absolutePadCenters(layout: FootprintPlacementLayout) -> [String: [KiCadSchematicDocument.Point]] {
        var result: [String: [KiCadSchematicDocument.Point]] = [:]
        for placed in layout.placements {
            for pin in placed.component.pins {
                let pad = pin.footprintPad ?? pin.pinNumber
                guard let localCenters = placed.geometry.padCenters[pad] else { continue }
                result["\(placed.component.refdes)|\(pin.pinNumber)"] = localCenters.map { local in
                    KiCadSchematicDocument.Point(
                        x: placed.at.x + local.x,
                        y: placed.at.y + local.y
                    )
                }
            }
        }
        return result
    }

    private func absoluteComponentPadCenters(layout: FootprintPlacementLayout) -> [String: [KiCadSchematicDocument.Point]] {
        var result: [String: [KiCadSchematicDocument.Point]] = [:]
        for placed in layout.placements {
            let centers = placed.geometry.padCenters.values.flatMap { localCenters in
                localCenters.map { local in
                    KiCadSchematicDocument.Point(
                        x: placed.at.x + local.x,
                        y: placed.at.y + local.y
                    )
                }
            }
            result[placed.component.refdes] = centers
        }
        return result
    }

    private func absoluteFootprintBounds(layout: FootprintPlacementLayout) -> [String: FootprintBounds] {
        Dictionary(uniqueKeysWithValues: layout.placements.map { placed in
            (placed.component.refdes, placed.geometry.bounds.translated(by: placed.at))
        })
    }

    private func escapeY(
        for point: KiCadSchematicDocument.Point,
        bounds: FootprintBounds,
        componentPadCenters: [KiCadSchematicDocument.Point],
        laneOffset: Double,
        outline: BoardOutline
    ) -> Double {
        let columnPads = componentPadCenters.filter { abs($0.x - point.x) < 0.25 }
        let shouldEscapeUp: Bool
        if columnPads.count > 1 {
            let ordered = columnPads.sorted { $0.y < $1.y }
            shouldEscapeUp = point.y <= (ordered.first!.y + ordered.last!.y) / 2
        } else {
            shouldEscapeUp = point.y <= bounds.midY
        }
        let rawEscapeY = shouldEscapeUp
            ? bounds.minY - laneOffset
            : bounds.maxY + laneOffset
        return min(max(rawEscapeY, 2.0), outline.heightMm - 2.0)
    }

    private func segmentNode(
        start: KiCadSchematicDocument.Point,
        end: KiCadSchematicDocument.Point,
        netID: Int,
        layer: String,
        discriminator: String
    ) -> String {
        if start.x == end.x && start.y == end.y {
            return ""
        }
        return #"  (segment (start \#(number(start.x)) \#(number(start.y))) (end \#(number(end.x)) \#(number(end.y))) (width 0.25) (layer "\#(layer)") (net \#(netID)) (uuid "\#(stableUUID("segment", discriminator))"))"#
    }

    private func viaNode(
        at: KiCadSchematicDocument.Point,
        netID: Int,
        discriminator: String
    ) -> String {
        #"  (via (at \#(number(at.x)) \#(number(at.y))) (size 0.8) (drill 0.4) (layers "F.Cu" "B.Cu") (net \#(netID)) (uuid "\#(stableUUID("via", discriminator))"))"#
    }

    private func firstPair(pattern: String, in text: String) -> (x: Double, y: Double)? {
        guard let match = regexMatches(pattern, in: text).first,
              match.count == 3,
              let x = Double(match[1]),
              let y = Double(match[2]) else {
            return nil
        }
        return (x, y)
    }

    private func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private func ensureFootprintPlacement(
        _ text: String,
        component: CircuitComponent,
        at: KiCadSchematicDocument.Point
    ) -> String {
        let placement = #"(at \#(number(at.x)) \#(number(at.y)) 0)"#
        let result = insertAfterFirstNode(named: "layer", in: text, node: "\t\(placement)")
        return insertAfterFirstNode(
            named: "at",
            in: result,
            node: "\t(uuid \"\(stableUUID("footprint", component.refdes))\")"
        )
    }

    private func rewriteFootprintProperty(_ text: String, name: String, value: String) -> String {
        let replaced = replaceFirstMatching(
            text,
            pattern: #"\(property\s+"\#(NSRegularExpression.escapedPattern(for: name))"\s+"(?:[^"\\]|\\.)*""#,
            replacement: #"(property "\#(escaped(name))" "\#(escaped(value))""#
        )
        if replaced != text {
            return replaced
        }
        return insertAfterFirstNode(
            named: "at",
            in: text,
            node: "\t(property \"\(escaped(name))\" \"\(escaped(value))\" (at 0 0 0) (layer \"F.Fab\") (uuid \"\(stableUUID("property", value, name))\"))"
        )
    }

    private func rewriteFootprintText(_ text: String, kind: String, value: String) -> String {
        replaceFirstMatching(
            text,
            pattern: #"\(fp_text\s+\#(NSRegularExpression.escapedPattern(for: kind))\s+"(?:[^"\\]|\\.)*""#,
            replacement: #"(fp_text \#(kind) "\#(escaped(value))""#
        )
    }

    private func rewriteFootprintPadNets(
        _ text: String,
        component: CircuitComponent,
        netIDs: [String: Int],
        pinNetNames: [String: String]
    ) -> String {
        var result = text
        var searchIndex = result.startIndex
        while let padStart = result[searchIndex...].range(of: "(pad ")?.lowerBound,
              let padEnd = balancedNodeEnd(in: result, start: padStart) {
            let originalBlock = String(result[padStart..<padEnd])
            let padName = firstQuotedValue(in: originalBlock)
            let netName = padName.flatMap { pad in
                component.pins.first(where: { ($0.footprintPad ?? $0.pinNumber) == pad })
                    .flatMap { pinNetNames["\(component.refdes)|\($0.pinNumber)"] }
            } ?? ""
            let replacement: String
            if let netID = netIDs[netName], netID > 0 {
                replacement = replaceOrInsertNet(
                    in: originalBlock,
                    netID: netID,
                    netName: netName
                )
            } else {
                replacement = originalBlock
            }
            result.replaceSubrange(padStart..<padEnd, with: replacement)
            searchIndex = result.index(padStart, offsetBy: replacement.count, limitedBy: result.endIndex) ?? result.endIndex
        }
        return result
    }

    private func replaceOrInsertNet(in padBlock: String, netID: Int, netName: String) -> String {
        let netNode = #"(net \#(netID) "\#(escaped(netName))")"#
        let replaced = replaceFirstNode(named: "net", in: padBlock, with: "\t\t\(netNode)")
        if replaced != padBlock {
            return replaced
        }
        guard let final = padBlock.lastIndex(of: ")") else { return padBlock }
        var result = padBlock
        result.insert(contentsOf: "\n\t\t\(netNode)", at: final)
        return result
    }

    private func rewriteUUIDs(_ text: String, component: CircuitComponent) -> String {
        var count = 0
        return replaceAllMatching(text, pattern: #"\(uuid\s+"[^"]+"\)"#) {
            count += 1
            return #"(uuid "\#(stableUUID("footprint-uuid", component.refdes, "\(count)"))")"#
        }
    }

    private func replaceFirstNode(named name: String, in text: String, with replacement: String) -> String {
        guard let start = text.range(of: "(\(name) ")?.lowerBound,
              let end = balancedNodeEnd(in: text, start: start) else {
            return text
        }
        var result = text
        result.replaceSubrange(start..<end, with: replacement)
        return result
    }

    private func insertAfterFirstNode(named name: String, in text: String, node: String) -> String {
        guard let start = text.range(of: "(\(name) ")?.lowerBound,
              let end = balancedNodeEnd(in: text, start: start) else {
            return text
        }
        var result = text
        result.insert(contentsOf: "\n\(node)", at: end)
        return result
    }

    private func balancedNodeEnd(in text: String, start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escapedCharacter = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escapedCharacter {
                    escapedCharacter = false
                } else if character == "\\" {
                    escapedCharacter = true
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

    private func firstQuotedValue(in text: String) -> String? {
        guard let firstQuote = text.firstIndex(of: "\""),
              let secondQuote = text[text.index(after: firstQuote)...].firstIndex(of: "\"") else {
            return nil
        }
        return String(text[text.index(after: firstQuote)..<secondQuote])
    }

    private func replaceFirstMatching(_ text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private func replaceAllMatching(
        _ text: String,
        pattern: String,
        replacement: () -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
        var result = text
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement())
        }
        return result
    }

    private func padNode(
        component: CircuitComponent,
        pin: CircuitPin,
        padIndex: Int,
        netIDs: [String: Int],
        pinNetNames: [String: String]
    ) -> String {
        let pad = escaped(pin.footprintPad ?? pin.pinNumber)
        let netName = pinNetNames["\(component.refdes)|\(pin.pinNumber)"] ?? ""
        let netID = netIDs[netName] ?? 0
        let net = netID == 0 ? "" : #" (net \#(netID) "\#(escaped(netName))")"#
        let x = Double(padIndex) * 2.54
        return #"    (pad "\#(pad)" thru_hole circle (at \#(number(x)) 0) (size 1.6 1.6) (drill 0.8) (layers "*.Cu" "*.Mask")\#(net) (uuid "\#(stableUUID("pad", component.refdes, pad))"))"#
    }

    private func netIDsByName(circuitIR: CircuitIR) -> [String: Int] {
        var result: [String: Int] = [:]
        for net in circuitIR.nets where !net.endpoints.isEmpty && result[net.name] == nil {
            result[net.name] = result.count + 1
        }
        return result
    }

    private func netNamesByEndpoint(circuitIR: CircuitIR) -> [String: String] {
        var result: [String: String] = [:]
        for net in circuitIR.nets {
            for endpoint in net.endpoints {
                result["\(endpoint.componentRefdes)|\(endpoint.pinNumber)"] = net.name
            }
        }
        return result
    }

    private func issue(_ code: String, _ message: String) -> ElectronicsSchemaIssue {
        ElectronicsSchemaIssue(code: code, message: message)
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == floor(rounded) {
            return String(Int(rounded))
        }
        return String(format: "%.3f", rounded).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    private func stableUUID(_ parts: String...) -> String {
        let input = parts.joined(separator: "|")
        let hash = input.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

struct FootprintAssignmentVerifier: Sendable {
    func verify(
        circuitIR: CircuitIR,
        resolutions: [KiCadLibraryPinResolution]
    ) -> ElectronicsSchemaValidationResult {
        var issues: [ElectronicsSchemaIssue] = []
        let byRef = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.componentRefdes, $0) })

        for component in circuitIR.components {
            guard let resolution = byRef[component.refdes],
                  resolution.isResolved,
                  resolution.footprintEvidence != nil else {
                issues.append(ElectronicsSchemaIssue(
                    code: "FOOTPRINT_PIN_PROOF_MISSING",
                    message: "\(component.refdes) has no resolved footprint proof."
                ))
                continue
            }
            for pin in component.pins where resolution.pinPadMap[pin.symbolPin] == nil {
                issues.append(ElectronicsSchemaIssue(
                    code: "FOOTPRINT_PIN_PROOF_MISSING",
                    message: "\(component.refdes).\(pin.pinNumber) has no pin-pad proof."
                ))
            }
            for issue in resolution.issues {
                issues.append(ElectronicsSchemaIssue(
                    code: "FOOTPRINT_PIN_PROOF_MISSING",
                    message: "\(issue.affectedRef): \(issue.message)"
                ))
            }
        }

        return ElectronicsSchemaValidationResult(issues: issues)
    }
}

enum KiCadDRCSeverity: String, Codable, Sendable, Equatable {
    case error
    case warning
    case info

    var isBlocking: Bool {
        self == .error
    }
}

struct KiCadDRCViolation: Codable, Sendable, Equatable {
    var id: String
    var code: String
    var severity: KiCadDRCSeverity
    var message: String
    var refs: [String]
}

struct KiCadDRCReport: Codable, Sendable, Equatable {
    var violations: [KiCadDRCViolation]

    var blockingViolations: [KiCadDRCViolation] {
        violations.filter { $0.severity.isBlocking }
    }
}

struct KiCadDRCParser: Sendable {
    func parse(jsonData: Data) throws -> KiCadDRCReport {
        let root = try JSONDecoder().decode(FlexibleDRCReport.self, from: jsonData)
        return KiCadDRCReport(violations: root.violations.map(\.violation))
    }
}

enum PCBDRCRepairClass: String, Codable, Sendable, Equatable {
    case placement
    case routing
    case netClass = "net_class"
    case clearance
}

struct PCBDRCRepairPatch: Codable, Sendable, Equatable {
    var violationId: String
    var repairClass: PCBDRCRepairClass
    var targetRefs: [String]
    var action: String
}

enum PCBDRCRepairLoopStatus: String, Codable, Sendable, Equatable {
    case verified
    case blocked
}

struct PCBDRCRepairLoopResult: Codable, Sendable, Equatable {
    var status: PCBDRCRepairLoopStatus
    var attempts: Int
    var appliedPatches: [PCBDRCRepairPatch]
    var diagnostics: [ElectronicsSchemaIssue]
}

struct PCBDRCRepairLoop: Sendable {
    var maxAttempts: Int = 3

    func run(drcReports: [KiCadDRCReport]) -> PCBDRCRepairLoopResult {
        var attempts = 0
        var applied: [PCBDRCRepairPatch] = []
        let reports = drcReports.isEmpty ? [KiCadDRCReport(violations: [])] : drcReports

        for report in reports {
            if report.blockingViolations.isEmpty {
                return PCBDRCRepairLoopResult(status: .verified, attempts: attempts, appliedPatches: applied, diagnostics: [])
            }
            if attempts >= maxAttempts {
                return blocked(
                    attempts: attempts,
                    applied: applied,
                    code: "DRC_REPAIR_ATTEMPTS_EXHAUSTED",
                    message: "DRC repair attempts exhausted before KiCad reported a clean PCB."
                )
            }

            var patches: [PCBDRCRepairPatch] = []
            for violation in report.blockingViolations {
                switch classify(violation) {
                case .repair(let repairClass):
                    patches.append(PCBDRCRepairPatch(
                        violationId: violation.id,
                        repairClass: repairClass,
                        targetRefs: violation.refs,
                        action: actionName(for: repairClass)
                    ))
                case .requiresApproval:
                    return blocked(
                        attempts: attempts,
                        applied: applied,
                        code: "DRC_REPAIR_REQUIRES_APPROVAL",
                        message: violation.message
                    )
                case .unsupported:
                    return blocked(
                        attempts: attempts,
                        applied: applied,
                        code: "UNSUPPORTED_DRC_VIOLATION",
                        message: violation.code
                    )
                }
            }

            attempts += 1
            applied.append(contentsOf: patches)
        }

        return blocked(
            attempts: attempts,
            applied: applied,
            code: "DRC_REPAIR_ATTEMPTS_EXHAUSTED",
            message: "DRC repair loop ended without a clean DRC report."
        )
    }

    private enum Classification {
        case repair(PCBDRCRepairClass)
        case requiresApproval
        case unsupported
    }

    private func classify(_ violation: KiCadDRCViolation) -> Classification {
        switch violation.code {
        case "courtyard_collision", "courtyards_overlap", "placement_overlap", "component_collision", "pth_inside_courtyard", "silk_overlap":
            return .repair(.placement)
        case "unrouted_net", "routing_incomplete":
            return .repair(.routing)
        case "net_class", "track_width":
            return .repair(.netClass)
        case "clearance", "copper_clearance":
            return .repair(.clearance)
        case "layer_count_change_required", "fabricator_profile_change_required":
            return .requiresApproval
        default:
            return .unsupported
        }
    }

    private func actionName(for repairClass: PCBDRCRepairClass) -> String {
        switch repairClass {
        case .placement:
            return "adjust_placement"
        case .routing:
            return "reroute_or_report_unrouted"
        case .netClass:
            return "adjust_net_class"
        case .clearance:
            return "adjust_clearance_rule"
        }
    }

    private func blocked(
        attempts: Int,
        applied: [PCBDRCRepairPatch],
        code: String,
        message: String
    ) -> PCBDRCRepairLoopResult {
        PCBDRCRepairLoopResult(
            status: .blocked,
            attempts: attempts,
            appliedPatches: applied,
            diagnostics: [ElectronicsSchemaIssue(code: code, message: message)]
        )
    }
}

enum PCBVerificationEvidenceKey: String, Codable, Sendable, Equatable {
    case schematicVerified = "schematic_verified"
    case footprintAssignment = "footprint_assignment"
    case boardProfile = "board_profile"
    case boardOutline = "board_outline"
    case stackup = "stackup"
    case netClasses = "net_classes"
    case placement = "placement"
    case routing = "routing"
    case drcReport = "drc_report"
    case pcbVerificationReport = "pcb_verification_report"
}

enum PCBVerificationStatus: String, Codable, Sendable, Equatable {
    case pcbVerified = "PCB_VERIFIED"
    case blocked = "BLOCKED"
}

struct PCBVerificationEvidence: Codable, Sendable, Equatable {
    var schematicVerified: Bool
    var footprintAssignmentPassed: Bool
    var hasBoardProfile: Bool
    var hasBoardOutline: Bool
    var hasStackup: Bool
    var hasNetClasses: Bool
    var hasPlacement: Bool
    var routingPassedOrExplicitlyDiagnosed: Bool
    var drcReportPath: String?
    var hasPCBVerificationReport: Bool
    var blockingDRCViolations: [KiCadDRCViolation]
    var repairLoopStatus: PCBDRCRepairLoopStatus

    enum CodingKeys: String, CodingKey {
        case schematicVerified
        case footprintAssignmentPassed
        case hasBoardProfile
        case hasBoardOutline
        case hasStackup
        case hasNetClasses
        case hasPlacement
        case routingPassedOrExplicitlyDiagnosed
        case drcReportPath
        case hasPCBVerificationReport
        case blockingDRCViolations
        case repairLoopStatus
    }

    init(
        schematicVerified: Bool,
        footprintAssignmentPassed: Bool,
        hasBoardProfile: Bool,
        hasBoardOutline: Bool,
        hasStackup: Bool,
        hasNetClasses: Bool,
        hasPlacement: Bool,
        routingPassedOrExplicitlyDiagnosed: Bool,
        drcReportPath: String?,
        hasPCBVerificationReport: Bool,
        blockingDRCViolations: [KiCadDRCViolation],
        repairLoopStatus: PCBDRCRepairLoopStatus
    ) {
        self.schematicVerified = schematicVerified
        self.footprintAssignmentPassed = footprintAssignmentPassed
        self.hasBoardProfile = hasBoardProfile
        self.hasBoardOutline = hasBoardOutline
        self.hasStackup = hasStackup
        self.hasNetClasses = hasNetClasses
        self.hasPlacement = hasPlacement
        self.routingPassedOrExplicitlyDiagnosed = routingPassedOrExplicitlyDiagnosed
        self.drcReportPath = drcReportPath
        self.hasPCBVerificationReport = hasPCBVerificationReport
        self.blockingDRCViolations = blockingDRCViolations
        self.repairLoopStatus = repairLoopStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PCBVerificationFlexibleCodingKey.self)
        schematicVerified = try container.decodeBool(keys: ["schematicVerified", "schematic_verified"])
        footprintAssignmentPassed = try container.decodeBool(keys: ["footprintAssignmentPassed", "footprint_assignment_passed"])
        hasBoardProfile = try container.decodeBool(keys: ["hasBoardProfile", "has_board_profile"])
        hasBoardOutline = try container.decodeBool(keys: ["hasBoardOutline", "has_board_outline"])
        hasStackup = try container.decodeBool(keys: ["hasStackup", "has_stackup"])
        hasNetClasses = try container.decodeBool(keys: ["hasNetClasses", "has_net_classes"])
        hasPlacement = try container.decodeBool(keys: ["hasPlacement", "has_placement"])
        routingPassedOrExplicitlyDiagnosed = try container.decodeBool(
            keys: ["routingPassedOrExplicitlyDiagnosed", "routing_passed_or_explicitly_diagnosed"]
        )
        drcReportPath = try container.decodeStringIfPresent(keys: ["drcReportPath", "drc_report_path"])
        hasPCBVerificationReport = try container.decodeBool(keys: [
            "hasPCBVerificationReport",
            "hasPcbVerificationReport",
            "has_pcb_verification_report",
        ])
        blockingDRCViolations = try container.decodeArrayIfPresent(
            [KiCadDRCViolation].self,
            keys: ["blockingDRCViolations", "blockingDrcViolations", "blocking_drc_violations"]
        ) ?? []
        repairLoopStatus = try container.decodeStatus(keys: ["repairLoopStatus", "repair_loop_status"])
    }

    static let missingEvidence = PCBVerificationEvidence(
        schematicVerified: false,
        footprintAssignmentPassed: false,
        hasBoardProfile: false,
        hasBoardOutline: false,
        hasStackup: false,
        hasNetClasses: false,
        hasPlacement: false,
        routingPassedOrExplicitlyDiagnosed: false,
        drcReportPath: nil,
        hasPCBVerificationReport: false,
        blockingDRCViolations: [],
        repairLoopStatus: .blocked
    )

    static let complete = PCBVerificationEvidence(
        schematicVerified: true,
        footprintAssignmentPassed: true,
        hasBoardProfile: true,
        hasBoardOutline: true,
        hasStackup: true,
        hasNetClasses: true,
        hasPlacement: true,
        routingPassedOrExplicitlyDiagnosed: true,
        drcReportPath: "/tmp/drc.json",
        hasPCBVerificationReport: true,
        blockingDRCViolations: [],
        repairLoopStatus: .verified
    )
}

private struct PCBVerificationFlexibleCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == PCBVerificationFlexibleCodingKey {
    func decodeBool(keys: [String]) throws -> Bool {
        for key in keys {
            guard let codingKey = PCBVerificationFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            return try decode(Bool.self, forKey: codingKey)
        }
        throw DecodingError.keyNotFound(
            PCBVerificationFlexibleCodingKey(stringValue: keys.first ?? "")!,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing PCB verification evidence key.")
        )
    }

    func decodeStringIfPresent(keys: [String]) throws -> String? {
        for key in keys {
            guard let codingKey = PCBVerificationFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            return try decodeIfPresent(String.self, forKey: codingKey)
        }
        return nil
    }

    func decodeArrayIfPresent<T: Decodable>(_ type: [T].Type, keys: [String]) throws -> [T]? {
        for key in keys {
            guard let codingKey = PCBVerificationFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            return try decodeIfPresent(type, forKey: codingKey)
        }
        return nil
    }

    func decodeStatus(keys: [String]) throws -> PCBDRCRepairLoopStatus {
        for key in keys {
            guard let codingKey = PCBVerificationFlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            return try decode(PCBDRCRepairLoopStatus.self, forKey: codingKey)
        }
        throw DecodingError.keyNotFound(
            PCBVerificationFlexibleCodingKey(stringValue: keys.first ?? "")!,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing PCB DRC repair status key.")
        )
    }
}

struct PCBVerificationReport: Codable, Sendable, Equatable {
    var status: PCBVerificationStatus
    var statusCode: String
    var missingEvidence: [PCBVerificationEvidenceKey]
    var diagnostics: [ElectronicsSchemaIssue]
    var fabricationComplete: Bool
}

struct PCBVerificationResult: Codable, Sendable, Equatable {
    var status: PCBVerificationStatus
    var report: PCBVerificationReport
    var missingEvidence: [PCBVerificationEvidenceKey]
    var diagnostics: [ElectronicsSchemaIssue]
}

struct PCBVerificationGate: Sendable {
    func evaluate(_ evidence: PCBVerificationEvidence) -> PCBVerificationResult {
        var missing: [PCBVerificationEvidenceKey] = []
        var diagnostics: [ElectronicsSchemaIssue] = []

        if !evidence.schematicVerified { missing.append(.schematicVerified) }
        if !evidence.footprintAssignmentPassed { missing.append(.footprintAssignment) }
        if !evidence.hasBoardProfile { missing.append(.boardProfile) }
        if !evidence.hasBoardOutline { missing.append(.boardOutline) }
        if !evidence.hasStackup { missing.append(.stackup) }
        if !evidence.hasNetClasses { missing.append(.netClasses) }
        if !evidence.hasPlacement { missing.append(.placement) }
        if !evidence.routingPassedOrExplicitlyDiagnosed { missing.append(.routing) }
        if evidence.drcReportPath?.isEmpty ?? true { missing.append(.drcReport) }
        if !evidence.hasPCBVerificationReport { missing.append(.pcbVerificationReport) }

        diagnostics.append(contentsOf: evidence.blockingDRCViolations.map {
            ElectronicsSchemaIssue(code: "BLOCKING_DRC_VIOLATION", message: $0.message)
        })
        if evidence.repairLoopStatus != .verified {
            diagnostics.append(ElectronicsSchemaIssue(
                code: "PCB_DRC_NOT_VERIFIED",
                message: "DRC repair loop has not reached a verified PCB state."
            ))
        }

        let status: PCBVerificationStatus = missing.isEmpty && diagnostics.isEmpty ? .pcbVerified : .blocked
        let report = PCBVerificationReport(
            status: status,
            statusCode: status.rawValue,
            missingEvidence: missing,
            diagnostics: diagnostics,
            fabricationComplete: false
        )

        return PCBVerificationResult(status: status, report: report, missingEvidence: missing, diagnostics: diagnostics)
    }
}

private struct FlexibleDRCReport: Decodable {
    var violations: [FlexibleDRCViolation]

    enum CodingKeys: String, CodingKey {
        case violations
        case errors
        case unconnectedItems = "unconnected_items"
        case sheets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let topLevel = try container.decodeIfPresent([FlexibleDRCViolation].self, forKey: .violations)
            ?? container.decodeIfPresent([FlexibleDRCViolation].self, forKey: .errors)
            ?? []
        let unconnected = try container.decodeIfPresent([FlexibleDRCViolation].self, forKey: .unconnectedItems) ?? []
        let sheetLevel = try container.decodeIfPresent([FlexibleDRCSheet].self, forKey: .sheets)?
            .flatMap(\.violations) ?? []
        violations = topLevel + unconnected + sheetLevel
    }
}

private struct FlexibleDRCSheet: Decodable {
    var violations: [FlexibleDRCViolation]

    enum CodingKeys: String, CodingKey {
        case violations
        case errors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        violations = try container.decodeIfPresent([FlexibleDRCViolation].self, forKey: .violations)
            ?? container.decodeIfPresent([FlexibleDRCViolation].self, forKey: .errors)
            ?? []
    }
}

private struct FlexibleDRCViolation: Decodable {
    var violation: KiCadDRCViolation

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case type
        case severity
        case message
        case description
        case refs
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        let code = try container.decodeIfPresent(String.self, forKey: .code)
            ?? container.decodeIfPresent(String.self, forKey: .type)
            ?? "unknown"
        let severityText = (try container.decodeIfPresent(String.self, forKey: .severity) ?? "error").lowercased()
        let severity = KiCadDRCSeverity(rawValue: severityText) ?? .error
        let message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .description)
            ?? code
        let refs = try container.decodeIfPresent([String].self, forKey: .refs)
            ?? FlexibleDRCItemRefs.decode(from: decoder, key: .items)
            ?? []
        violation = KiCadDRCViolation(id: id, code: code, severity: severity, message: message, refs: refs)
    }
}

private enum FlexibleDRCItemRefs {
    static func decode(from decoder: Decoder, key: FlexibleDRCViolation.CodingKeys) -> [String]? {
        guard let container = try? decoder.container(keyedBy: FlexibleDRCViolation.CodingKeys.self),
              container.contains(key) else {
            return nil
        }
        if let strings = try? container.decode([String].self, forKey: key) {
            return strings
        }
        if let objects = try? container.decode([FlexibleDRCItem].self, forKey: key) {
            return objects.map(\.reference).filter { !$0.isEmpty }
        }
        return nil
    }
}

private struct FlexibleDRCItem: Decodable {
    var reference: String

    enum CodingKeys: String, CodingKey {
        case ref
        case reference
        case description
        case uuid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decodeIfPresent(String.self, forKey: .ref)
            ?? container.decodeIfPresent(String.self, forKey: .reference)
            ?? container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .uuid)
            ?? ""
    }
}
