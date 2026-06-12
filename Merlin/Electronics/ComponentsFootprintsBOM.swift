import Foundation

enum FootprintAssignmentSource: String, Codable, Sendable, Equatable {
    case existingKiCadField = "existing_kicad_field"
    case exactMPN = "exact_mpn"
    case packageConstraint = "package_constraint"
    case projectDefault = "project_default"
    case userClarification = "user_clarification"
    case unknown = "unknown"
}

struct FootprintAssignment: Codable, Sendable, Equatable {
    var refdes: String
    var footprint: String
    var source: FootprintAssignmentSource
    var pinPadMap: [String: String]
    var sourceProviderID: String
    var sourcePath: String?
    var packageCompatibilityEvidence: String

    enum CodingKeys: String, CodingKey {
        case refdes
        case footprint
        case source
        case pinPadMap = "pin_pad_map"
        case sourceProviderID = "source_provider_id"
        case sourcePath = "source_path"
        case packageCompatibilityEvidence = "package_compatibility_evidence"
    }

    init(refdes: String,
         footprint: String,
         source: FootprintAssignmentSource,
         pinPadMap: [String: String] = [:],
         sourceProviderID: String = "",
         sourcePath: String? = nil,
         packageCompatibilityEvidence: String = "") {
        self.refdes = refdes
        self.footprint = footprint
        self.source = source
        self.pinPadMap = pinPadMap
        self.sourceProviderID = sourceProviderID
        self.sourcePath = sourcePath
        self.packageCompatibilityEvidence = packageCompatibilityEvidence
    }
}

struct FootprintAssignmentReport: Codable, Sendable, Equatable {
    var assignments: [FootprintAssignment]
    var unknownFootprints: Int

    var status: KiCadStatus {
        unknownFootprints > 0 ? .blockedInputQuality : .complete
    }

    var mayProceedToPCBSynthesis: Bool {
        unknownFootprints == 0
    }
}

struct FootprintAssignmentPolicy: Sendable {
    func assign(refdes: String,
                existingKiCadFootprint: String?,
                exactMPNFootprint: String?,
                packageConstraintFootprint: String?,
                projectDefaultFootprint: String?,
                userClarifiedFootprint: String?) -> FootprintAssignment {
        if let existingKiCadFootprint, !existingKiCadFootprint.isEmpty {
            return FootprintAssignment(refdes: refdes, footprint: existingKiCadFootprint, source: .existingKiCadField)
        }
        if let exactMPNFootprint, !exactMPNFootprint.isEmpty {
            return FootprintAssignment(refdes: refdes, footprint: exactMPNFootprint, source: .exactMPN)
        }
        if let packageConstraintFootprint, !packageConstraintFootprint.isEmpty {
            return FootprintAssignment(refdes: refdes, footprint: packageConstraintFootprint, source: .packageConstraint)
        }
        if let projectDefaultFootprint, !projectDefaultFootprint.isEmpty {
            return FootprintAssignment(refdes: refdes, footprint: projectDefaultFootprint, source: .projectDefault)
        }
        if let userClarifiedFootprint, !userClarifiedFootprint.isEmpty {
            return FootprintAssignment(refdes: refdes, footprint: userClarifiedFootprint, source: .userClarification)
        }
        return FootprintAssignment(refdes: refdes, footprint: "UNKNOWN", source: .unknown)
    }
}

struct ComponentLibraryPolicy: Codable, Sendable, Equatable {
    var requireGeneratedAssetVerification: Bool

    static let `default` = ComponentLibraryPolicy(requireGeneratedAssetVerification: true)
}

struct LibraryVerificationReport: Codable, Sendable, Equatable {
    var passed: Bool
    var requiredChecks: [String]
}

struct LibraryVerificationPolicy: Sendable {
    func verify(generatedSymbolPinNames: [String],
                generatedFootprintPads: [String],
                expectedPinNames: [String],
                expectedPadNumbers: [String],
                packageDimensionsMatch: Bool) -> LibraryVerificationReport {
        var requiredChecks: [String] = []

        let pinCountMismatch = generatedSymbolPinNames.count != expectedPinNames.count
        let pinNameMismatch = Set(generatedSymbolPinNames) != Set(expectedPinNames)
        let padMismatch = Set(generatedFootprintPads) != Set(expectedPadNumbers)
        let packageMismatch = !packageDimensionsMatch

        if pinCountMismatch || padMismatch || packageMismatch {
            requiredChecks.append("pin_count")
        }
        if pinNameMismatch || padMismatch || packageMismatch {
            requiredChecks.append("pin_name")
        }
        if padMismatch {
            requiredChecks.append("pad_number")
        }
        if packageMismatch {
            requiredChecks.append("package_dimension")
        }

        return LibraryVerificationReport(passed: requiredChecks.isEmpty, requiredChecks: requiredChecks)
    }
}

struct NormalizedBOMBuilder: Sendable {
    func build(designId: String, kicadRows: [[String: String]]) -> NormalizedBOM {
        var lines: [BOMLine] = []
        var mappings: [VendorBOMMapping] = []

        for (index, row) in kicadRows.enumerated() {
            let refdes = splitCSV(row["RefDes"]) 
            let quantity = Int(row["quantity"] ?? "") ?? max(refdes.count, 1)
            let vendorSKUs = parseVendorSKUs(row["vendor_skus"] ?? "")

            let line = BOMLine(
                lineId: "line-\(index + 1)",
                mpn: row["MPN"] ?? "",
                quantity: quantity,
                referenceDesignators: refdes,
                value: row["value"],
                footprint: row["footprint"],
                manufacturer: row["manufacturer"],
                vendorSKUs: vendorSKUs,
                dnp: parseBool(row["DNP"] ?? "false"),
                lifecycle: row["lifecycle"] ?? "",
                substitutions: splitCSV(row["substitutions"])
            )
            lines.append(line)

            for (vendor, sku) in vendorSKUs {
                mappings.append(VendorBOMMapping(
                    vendorId: vendor,
                    lineId: line.lineId,
                    vendorPartNumber: sku
                ))
            }
        }

        return NormalizedBOM(
            designId: designId,
            lines: lines,
            vendorMappings: mappings,
            substitutions: []
        )
    }

    private func splitCSV(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseBool(_ value: String) -> Bool {
        ["1", "true", "yes", "y"].contains(value.lowercased())
    }

    private func parseVendorSKUs(_ value: String) -> [String: String] {
        var result: [String: String] = [:]
        for entry in value.split(separator: ";") {
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                result[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }
}

struct VendorSource: Codable, Sendable, Equatable {
    var canonicalName: String
    var aliases: [String]
}

struct VendorSourcePolicy: Codable, Sendable, Equatable {
    var supportedVendors: [VendorSource]

    static let `default` = VendorSourcePolicy(
        supportedVendors: [
            VendorSource(canonicalName: "Digi-Key", aliases: ["Digikey", "DigiKey"]),
            VendorSource(canonicalName: "Mouser", aliases: []),
            VendorSource(canonicalName: "Arrow", aliases: []),
            VendorSource(canonicalName: "Newark", aliases: []),
            VendorSource(canonicalName: "Farnell", aliases: []),
            VendorSource(canonicalName: "element14", aliases: ["Element14"]),
            VendorSource(canonicalName: "LCSC", aliases: []),
            VendorSource(canonicalName: "Parts Express", aliases: []),
        ]
    )
}

struct SubstitutionDecision: Codable, Sendable, Equatable {
    var requiresApproval: Bool
    var reasons: [String]
}

struct SubstitutionPolicy: Sendable {
    func evaluate(original: BOMLine, candidate: BOMLine) -> SubstitutionDecision {
        var reasons: [String] = []

        if original.footprint != candidate.footprint {
            reasons.append("package_changed")
        }
        if original.lifecycle != candidate.lifecycle {
            reasons.append("lifecycle_changed")
        }
        if original.value != candidate.value {
            reasons.append("electrical_characteristics_changed")
        }

        return SubstitutionDecision(
            requiresApproval: !reasons.isEmpty,
            reasons: reasons
        )
    }
}

private struct BOMLineMetadata: Sendable, Equatable {
    var value: String
    var footprint: String
    var manufacturer: String
    var vendorSKUs: [String: String]
    var dnp: Bool
    var lifecycle: String
    var substitutions: [String]
}

private enum BOMLineMetadataStore {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var store: [String: BOMLineMetadata] = [:]

    static func set(_ metadata: BOMLineMetadata, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        store[key] = metadata
    }

    static func get(_ key: String) -> BOMLineMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }
}

extension BOMLine {
    private static func metadataKey(lineId: String, mpn: String, quantity: Int, referenceDesignators: [String]) -> String {
        "\(lineId)|\(mpn)|\(quantity)|\(referenceDesignators.joined(separator: ","))"
    }

    private var metadataKey: String {
        Self.metadataKey(lineId: lineId, mpn: mpn, quantity: quantity, referenceDesignators: referenceDesignators)
    }

    init(lineId: String,
         mpn: String,
         quantity: Int,
         referenceDesignators: [String],
         value: String? = nil,
         footprint: String? = nil,
         manufacturer: String? = nil,
         vendorSKUs: [String: String] = [:],
         dnp: Bool = false,
         lifecycle: String = "",
         substitutions: [String] = []) {
        self.init(
            lineId: lineId,
            mpn: mpn,
            quantity: quantity,
            referenceDesignators: referenceDesignators
        )

        BOMLineMetadataStore.set(
            BOMLineMetadata(
                value: value ?? "",
                footprint: footprint ?? "",
                manufacturer: manufacturer ?? "",
                vendorSKUs: vendorSKUs,
                dnp: dnp,
                lifecycle: lifecycle,
                substitutions: substitutions
            ),
            for: Self.metadataKey(
                lineId: lineId,
                mpn: mpn,
                quantity: quantity,
                referenceDesignators: referenceDesignators
            )
        )
    }

    var value: String {
        BOMLineMetadataStore.get(metadataKey)?.value ?? ""
    }

    var footprint: String {
        BOMLineMetadataStore.get(metadataKey)?.footprint ?? ""
    }

    var manufacturer: String {
        BOMLineMetadataStore.get(metadataKey)?.manufacturer ?? ""
    }

    var vendorSKUs: [String: String] {
        BOMLineMetadataStore.get(metadataKey)?.vendorSKUs ?? [:]
    }

    var dnp: Bool {
        BOMLineMetadataStore.get(metadataKey)?.dnp ?? false
    }

    var lifecycle: String {
        BOMLineMetadataStore.get(metadataKey)?.lifecycle ?? ""
    }

    var substitutions: [String] {
        BOMLineMetadataStore.get(metadataKey)?.substitutions ?? []
    }
}
