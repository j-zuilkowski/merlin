import CryptoKit
import Foundation

struct ComponentSearchRequest: Codable, Sendable, Equatable {
    var refdes: String
    var role: String
    var constraints: [String: String]
    var requiredEvidenceTypes: [String]
    var preferredVendors: [String]
    var excludedManufacturers: [String]
    var lifecyclePolicy: String

    enum CodingKeys: String, CodingKey {
        case refdes
        case role
        case constraints
        case requiredEvidenceTypes = "required_evidence_types"
        case preferredVendors = "preferred_vendors"
        case excludedManufacturers = "excluded_manufacturers"
        case lifecyclePolicy = "lifecycle_policy"
    }
}

struct ComponentCandidate: Codable, Sendable, Equatable {
    var mpn: String
    var manufacturer: String
    var normalizedCategory: String
    var value: String?
    var package: String
    var ratings: [String: String]
    var lifecycleState: String
    var availabilitySummary: String
    var datasheets: [DatasheetEvidence]
    var evidence: [ComponentEvidence]
    var footprintCandidates: [FootprintCandidate]

    enum CodingKeys: String, CodingKey {
        case mpn
        case manufacturer
        case normalizedCategory = "normalized_category"
        case value
        case package
        case ratings
        case lifecycleState = "lifecycle_state"
        case availabilitySummary = "availability_summary"
        case datasheets
        case evidence
        case footprintCandidates = "footprint_candidates"
    }
}

struct ComponentEvidence: Codable, Sendable, Equatable {
    var providerID: String
    var sourceURL: String?
    var localPath: String?
    var retrievedAt: String
    var cachePolicy: String
    var sha256: String?
    var extractedParameters: [String: String]
    var confidence: Double
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case sourceURL = "source_url"
        case localPath = "local_path"
        case retrievedAt = "retrieved_at"
        case cachePolicy = "cache_policy"
        case sha256
        case extractedParameters = "extracted_parameters"
        case confidence
        case warnings
    }
}

struct DatasheetEvidence: Codable, Sendable, Equatable {
    var manufacturer: String
    var mpn: String
    var url: String
    var localPath: String?
    var sha256: String?
    var providerID: String
    var retrievedAt: String
    var license: String
    var citations: [String]

    enum CodingKeys: String, CodingKey {
        case manufacturer
        case mpn
        case url
        case localPath = "local_path"
        case sha256
        case providerID = "provider_id"
        case retrievedAt = "retrieved_at"
        case license
        case citations
    }
}

struct FootprintCandidate: Codable, Sendable, Equatable {
    var library: String
    var name: String
    var packageCompatibilityEvidence: String
    var pinPadMap: [String: String]
    var sourceProviderID: String
    var sourcePath: String?
    var threeDModel: String?

    enum CodingKeys: String, CodingKey {
        case library
        case name
        case packageCompatibilityEvidence = "package_compatibility_evidence"
        case pinPadMap = "pin_pad_map"
        case sourceProviderID = "source_provider_id"
        case sourcePath = "source_path"
        case threeDModel = "three_d_model"
    }
}

enum PartSelectionStatus: String, Codable, Sendable, Equatable {
    case selected
    case ambiguous
    case blocked
    case requiresVendorResolution = "requires_vendor_resolution"
}

struct PartSelectionDecision: Codable, Sendable, Equatable {
    var refdes: String
    var status: PartSelectionStatus
    var selectedCandidate: ComponentCandidate?
    var candidateSet: [ComponentCandidate]
    var rationale: String
    var evidenceReferences: [ComponentEvidence]
    var unresolvedDecisions: [String]

    enum CodingKeys: String, CodingKey {
        case refdes
        case status
        case selectedCandidate = "selected_candidate"
        case candidateSet = "candidate_set"
        case rationale
        case evidenceReferences = "evidence_references"
        case unresolvedDecisions = "unresolved_decisions"
    }
}

struct ComponentMatrix: Codable, Sendable, Equatable {
    var designId: String
    var components: [ComponentIntent]
    var decisions: [PartSelectionDecision]
    var warnings: [String]
    var providers: [String]
    var cacheMetadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case components
        case decisions
        case warnings
        case providers
        case cacheMetadata = "cache_metadata"
    }

    init(
        designId: String,
        decisions: [PartSelectionDecision],
        warnings: [String],
        providers: [String],
        cacheMetadata: [String: String],
        components: [ComponentIntent] = []
    ) {
        self.designId = designId
        self.components = components
        self.decisions = decisions
        self.warnings = warnings
        self.providers = providers
        self.cacheMetadata = cacheMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        designId = try container.decode(String.self, forKey: .designId)
        components = try container.decodeIfPresent([ComponentIntent].self, forKey: .components) ?? []
        decisions = try container.decode([PartSelectionDecision].self, forKey: .decisions)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        providers = try container.decodeIfPresent([String].self, forKey: .providers) ?? []
        cacheMetadata = try container.decodeIfPresent([String: String].self, forKey: .cacheMetadata) ?? [:]
    }
}

enum ComponentMatrixSelectionState: Equatable {
    case complete
    case blocked
    case invalid
}

enum ComponentMatrixEvidence {
    static func selectionState(atPath path: String) -> ComponentMatrixSelectionState {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return .invalid
        }
        return selectionState(in: data)
    }

    static func selectionState(in data: Data) -> ComponentMatrixSelectionState {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .invalid
        }

        let decisionStates = selectionStates(in: object["decisions"] as? [[String: Any]])
        let legacyComponentStates = selectionStates(inLegacyComponents: object["components"] as? [[String: Any]])
        let states = decisionStates + legacyComponentStates
        if !states.isEmpty {
            return aggregate(states)
        }

        return .invalid
    }

    static func isCompleteSelectionArtifact(atPath path: String) -> Bool {
        selectionState(atPath: path) == .complete
    }

    static func isBlockedSelectionArtifact(atPath path: String) -> Bool {
        selectionState(atPath: path) == .blocked
    }

    private static func aggregate(_ states: [ComponentMatrixSelectionState]) -> ComponentMatrixSelectionState {
        guard states.allSatisfy({ $0 == .complete }) else { return .blocked }
        return .complete
    }

    private static func selectionStates(in decisions: [[String: Any]]?) -> [ComponentMatrixSelectionState] {
        guard let decisions, !decisions.isEmpty else { return [] }
        return decisions.map { decision in
            let status = normalizedStatus(decision["status"])
            guard status == PartSelectionStatus.selected.rawValue else { return .blocked }
            guard let candidate = decision["selected_candidate"] as? [String: Any],
                  hasConcreteCandidateIdentity(candidate) else {
                return .blocked
            }
            return .complete
        }
    }

    private static func selectionStates(inLegacyComponents components: [[String: Any]]?) -> [ComponentMatrixSelectionState] {
        guard let components, !components.isEmpty else { return [] }
        return components.map { component in
            let status = normalizedStatus(component["selection_status"])
            if !status.isEmpty, status != PartSelectionStatus.selected.rawValue {
                return .blocked
            }
            return hasConcreteCandidateIdentity(component) ? .complete : .blocked
        }
    }

    private static func normalizedStatus(_ value: Any?) -> String {
        (value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""
    }

    private static func hasConcreteCandidateIdentity(_ object: [String: Any]) -> Bool {
        let mpn = nonEmptyString(object["mpn"])
            ?? nonEmptyString(object["manufacturer_part_number"])
            ?? nonEmptyString(object["vendor_part"])
        let manufacturer = nonEmptyString(object["manufacturer"])
        return mpn != nil && manufacturer != nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ComponentCatalogValidationIssue: Codable, Sendable, Equatable {
    var code: String
    var message: String
}

struct ComponentCatalogValidationResult: Codable, Sendable, Equatable {
    var issues: [ComponentCatalogValidationIssue]

    var isValid: Bool {
        issues.isEmpty
    }

    func contains(code: String) -> Bool {
        issues.contains { $0.code == code }
    }
}

struct ComponentCatalogValidator: Sendable {
    func validate(_ candidate: ComponentCandidate) -> ComponentCatalogValidationResult {
        var issues: [ComponentCatalogValidationIssue] = []
        if candidate.mpn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue("MPN_REQUIRED", "Component candidate requires a manufacturer part number."))
        }
        if candidate.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue("MANUFACTURER_REQUIRED", "Component candidate requires a manufacturer."))
        }
        if candidate.package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue("PACKAGE_REQUIRED", "Component candidate requires package evidence."))
        }
        if candidate.ratings.isEmpty {
            issues.append(issue("RATINGS_REQUIRED", "Component candidate requires rating evidence."))
        }
        if candidate.datasheets.isEmpty && !hasCommodityPassiveProductEvidence(candidate) {
            issues.append(issue("DATASHEET_REQUIRED", "Component candidate requires datasheet evidence."))
        }
        if candidate.evidence.isEmpty || candidate.evidence.contains(where: { $0.providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(issue("PROVENANCE_REQUIRED", "Component candidate requires provider provenance."))
        }
        return ComponentCatalogValidationResult(issues: issues)
    }

    private func issue(_ code: String, _ message: String) -> ComponentCatalogValidationIssue {
        ComponentCatalogValidationIssue(code: code, message: message)
    }

    private func hasCommodityPassiveProductEvidence(_ candidate: ComponentCandidate) -> Bool {
        guard isCommodityPassive(candidate) else { return false }
        guard hasMeaningfulPassiveRating(candidate) else { return false }
        return candidate.evidence.contains { evidence in
            evidence.providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                && evidence.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                && !evidence.extractedParameters.isEmpty
        }
    }

    private func isCommodityPassive(_ candidate: ComponentCandidate) -> Bool {
        let text = ([
            candidate.normalizedCategory,
            candidate.value ?? "",
            candidate.package,
        ] + candidate.ratings.map { "\($0.key) \($0.value)" })
            .joined(separator: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        let excluded = [
            "transistor",
            "mosfet",
            "bjt",
            "jfet",
            "diode",
            "bridge",
            "rectifier",
            "regulator",
            "integrated circuit",
            " ic ",
            "connector",
            "jack",
            "switch",
            "relay",
            "fuse",
            "transformer",
            "inductor",
            "potentiometer",
            "trimmer",
        ]
        guard !excluded.contains(where: { text.contains($0) }) else { return false }
        return text.contains("resistor")
            || text.contains("resistance")
            || text.contains("capacitor")
            || text.contains("capacitance")
    }

    private func hasMeaningfulPassiveRating(_ candidate: ComponentCandidate) -> Bool {
        let dictionaries = [candidate.ratings] + candidate.evidence.map(\.extractedParameters)
        let keys = [
            "resistance",
            "resistance_ohms",
            "capacitance",
            "capacitance_f",
            "capacitance_uf",
            "voltage_v",
            "voltage_rating",
            "voltage_rating_dc",
            "voltage_rating_ac",
            "power_w",
            "power_rating",
            "tolerance",
        ]
        return dictionaries.contains { dictionary in
            keys.contains { key in
                dictionary[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        }
    }
}

protocol ComponentCatalogProvider: Sendable {
    var providerID: String { get }
    func search(_ request: ComponentSearchRequest) async throws -> [ComponentCandidate]
}

protocol CatalogHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: CatalogHTTPTransport {}

struct LiveCatalogSearchResult: Sendable, Equatable {
    var candidates: [ComponentCandidate]
    var rawResponse: Data
    var requestURL: URL?
}

protocol LiveCatalogProviderClient: ComponentCatalogProvider {
    func searchWithRawResponse(_ request: ComponentSearchRequest) async throws -> LiveCatalogSearchResult
}

enum LiveCatalogProviderError: Error, LocalizedError, Sendable, Equatable {
    case invalidEndpoint(String)
    case missingCredential(String)
    case httpStatus(Int)
    case rateLimited(retryAfterSeconds: Int?)
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            return "Invalid catalog provider endpoint: \(endpoint)"
        case .missingCredential(let name):
            return "Missing catalog provider credential: \(name)"
        case .httpStatus(let status):
            return "Catalog provider returned HTTP \(status)."
        case .rateLimited(let retryAfterSeconds):
            if let retryAfterSeconds {
                return "Catalog provider rate limit reached; retry after \(retryAfterSeconds) seconds."
            }
            return "Catalog provider rate limit reached."
        case .missingAccessToken:
            return "Catalog provider token response did not include an access token."
        }
    }
}

struct CatalogSearchQueryBuilder: Sendable {
    func keywords(for request: ComponentSearchRequest) -> [String] {
        uniqueTerms([keyword(for: request)] + fallbackKeywords(for: request))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func keyword(for request: ComponentSearchRequest) -> String {
        let constraints = request.constraints
        if let value = constraints["catalog_search_keyword"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        for key in ["manufacturer_part_number", "mpn"] {
            if let value = constraints[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        let family = componentFamily(for: request)
        var terms = [String]()
        if let family, !family.keyword.isEmpty {
            terms.append(family.keyword)
        }
        terms.append(contentsOf: valueTerms(from: constraints))
        if let package = constraints["package"] {
            terms.append(contentsOf: packageTerms(from: package))
        }
        if let footprint = constraints["selected_footprint"] {
            terms.append(contentsOf: footprintTerms(from: footprint))
        }
        if let family {
            terms.append(contentsOf: family.defaultTerms)
        }
        if family.map(shouldIncludeRoleTerms(for:)) ?? true {
            terms.append(contentsOf: roleTerms(from: request.role, excluding: family?.excludedRoleTokens ?? []))
        }

        let query = uniqueTerms(terms)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !query.isEmpty {
            return query
        }
        return [request.role, request.refdes]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private struct ComponentFamily {
        var keyword: String
        var defaultTerms: [String]
        var excludedRoleTokens: Set<String>
    }

    private func shouldIncludeRoleTerms(for family: ComponentFamily) -> Bool {
        let keyword = family.keyword.lowercased()
        return !(keyword == "resistor"
            || keyword == "capacitor"
            || keyword == "potentiometer"
            || keyword.contains("position connector")
            || keyword.contains("terminal block")
            || keyword.contains("bridge rectifier")
            || keyword.contains("transistor"))
    }

    private func componentFamily(for request: ComponentSearchRequest) -> ComponentFamily? {
        let refdes = request.refdes.uppercased()
        let role = request.role.lowercased()
        let symbol = (request.constraints["selected_symbol"] ?? "").lowercased()
        let category = [
            request.constraints["component_category"],
            request.constraints["category"],
            request.constraints["kind"],
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let combined = "\(category) \(role) \(symbol)"

        if refdes.hasPrefix("BR") || combined.contains("bridge") || combined.contains("rectifier") {
            return ComponentFamily(
                keyword: "bridge rectifier",
                defaultTerms: ["through hole"],
                excludedRoleTokens: ["bridge", "rectifier"]
            )
        }
        if refdes.hasPrefix("RV") || combined.contains("potentiometer") || combined.contains("pot") {
            return ComponentFamily(
                keyword: "potentiometer",
                defaultTerms: [],
                excludedRoleTokens: ["potentiometer", "control"]
            )
        }
        if refdes.hasPrefix("R") || combined.contains("resistor") || symbol.hasSuffix(":r") {
            return ComponentFamily(
                keyword: "resistor",
                defaultTerms: [],
                excludedRoleTokens: ["resistor"]
            )
        }
        if refdes.hasPrefix("C") || combined.contains("capacitor") || symbol.hasSuffix(":c") {
            return ComponentFamily(
                keyword: "capacitor",
                defaultTerms: [],
                excludedRoleTokens: ["capacitor"]
            )
        }
        if refdes.hasPrefix("Q") || combined.contains("transistor") || combined.contains("mosfet") || combined.contains("bjt") {
            let keyword = combined.contains("pnp") ? "PNP transistor" : "NPN transistor"
            let powerPrefix = combined.contains("power transistor")
                || combined.contains("power_transistor")
                || combined.contains("output transistor")
                || combined.contains("driver transistor")
                || combined.contains("driver_transistor")
                ? "power "
                : ""
            return ComponentFamily(
                keyword: keyword.replacingOccurrences(of: "transistor", with: "\(powerPrefix)transistor"),
                defaultTerms: [],
                excludedRoleTokens: ["transistor", "stage"]
            )
        }
        if refdes.hasPrefix("D") || combined.contains("diode") {
            return ComponentFamily(
                keyword: "diode",
                defaultTerms: [],
                excludedRoleTokens: ["diode"]
            )
        }
        if refdes.hasPrefix("J") || refdes.hasPrefix("P") || combined.contains("connector") || combined.contains("jack") {
            let pinCount = pinCount(from: request.constraints["required_pins"])
                ?? numericCount(from: request.constraints["positions"])
            let keyword = pinCount.map { "\($0) position connector" } ?? "connector"
            return ComponentFamily(
                keyword: keyword,
                defaultTerms: [],
                excludedRoleTokens: ["connector"]
            )
        }
        if refdes.hasPrefix("U") || combined.contains("regulator") || combined.contains("op amp") || combined.contains("opamp") {
            return ComponentFamily(
                keyword: combined.contains("regulator") ? "voltage regulator" : "integrated circuit",
                defaultTerms: [],
                excludedRoleTokens: ["ic", "regulator", "op", "amp"]
            )
        }
        return nil
    }

    private func fallbackKeywords(for request: ComponentSearchRequest) -> [String] {
        let refdes = request.refdes.uppercased()
        let constraints = request.constraints
        let category = [
            constraints["component_category"],
            constraints["category"],
            constraints["kind"],
            request.role,
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        var queries: [String] = []
        let packageTerms = packageTerms(from: constraints["package"] ?? "")
        let mounting = constraints["mounting"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let voltage = constraints["voltage_rating"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = constraints["current_rating"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let power = constraints["power_rating"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resistance = constraints["resistance"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let capacitance = constraints["capacitance"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tolerance = constraints["tolerance"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let positions = constraints["positions"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        if refdes.hasPrefix("BR") || category.contains("bridge") || category.contains("rectifier") {
            queries.append("bridge rectifier")
            if let current, !current.isEmpty {
                queries.append("bridge rectifier \(current)")
            }
            if let voltage, !voltage.isEmpty {
                queries.append("bridge rectifier \(voltage)")
            }
            if let current, let voltage, !current.isEmpty, !voltage.isEmpty {
                queries.append("bridge rectifier \(current) \(voltage)")
            }
            queries.append("GBU bridge rectifier")
            queries.append("KBPC bridge rectifier")
            return uniqueTerms(queries)
        }

        if refdes.hasPrefix("RV") || category.contains("potentiometer") || category.contains("pot") {
            queries.append("potentiometer")
            if let resistance, !resistance.isEmpty {
                queries.append("potentiometer \(resistance)")
                queries.append("linear potentiometer \(resistance)")
                queries.append("through hole potentiometer \(resistance)")
            }
            return uniqueTerms(queries)
        }

        if refdes.hasPrefix("R") || category.contains("resistor") {
            queries.append("resistor")
            if let resistance, !resistance.isEmpty {
                queries.append("resistor \(resistance)")
                queries.append("fixed resistor \(resistance)")
                queries.append("metal film resistor \(resistance)")
                if let tolerance, !tolerance.isEmpty {
                    queries.append("resistor \(resistance) \(tolerance)")
                    queries.append("fixed resistor \(resistance) \(tolerance)")
                    queries.append("metal film resistor \(resistance) \(tolerance)")
                }
                if let power, !power.isEmpty {
                    queries.append("resistor \(resistance) \(power)")
                    queries.append("fixed resistor \(resistance) \(power)")
                    queries.append("metal film resistor \(resistance) \(power)")
                }
                if let mounting, !mounting.isEmpty {
                    let mountingText = mounting.replacingOccurrences(of: "_", with: " ")
                    queries.append("resistor \(resistance) \(mountingText)")
                    queries.append("fixed resistor \(resistance) \(mountingText)")
                    queries.append("metal film resistor \(resistance) \(mountingText)")
                    if mountingText.lowercased().contains("through") {
                        queries.append("through hole fixed resistor \(resistance)")
                        queries.append("axial resistor \(resistance)")
                    }
                }
                if packageTerms.contains(where: { $0.lowercased().contains("axial") }) {
                    queries.append("axial resistor \(resistance)")
                    queries.append("axial metal film resistor \(resistance)")
                }
            }
            return uniqueTerms(queries)
        }

        if refdes.hasPrefix("C") || category.contains("capacitor") {
            queries.append("capacitor")
            if let capacitance, !capacitance.isEmpty {
                queries.append("capacitor \(capacitance)")
                if let voltage, !voltage.isEmpty {
                    queries.append("capacitor \(capacitance) \(voltage)")
                }
                if let mounting, !mounting.isEmpty {
                    queries.append("capacitor \(capacitance) \(mounting.replacingOccurrences(of: "_", with: " "))")
                }
            }
            return uniqueTerms(queries)
        }

        if refdes.hasPrefix("J") || refdes.hasPrefix("P") || category.contains("connector") || category.contains("terminal") || category.contains("jack") {
            if let positions, !positions.isEmpty {
                queries.append("\(positions) position connector")
                queries.append("\(positions) position terminal block")
            }
            if let current, !current.isEmpty {
                queries.append("connector \(current)")
                queries.append("terminal block \(current)")
            }
            queries.append("terminal block")
            queries.append("connector")
            return uniqueTerms(queries)
        }

        guard refdes.hasPrefix("Q") || category.contains("transistor") || category.contains("bjt") else {
            return []
        }

        let polarity = normalizedPolarity(from: constraints)
        let packageQueries = packageTerms
            .filter { $0.lowercased().hasPrefix("to") || $0.lowercased().hasPrefix("sot") }
            .map { "\(polarity) transistor \($0)" }
        queries.append(contentsOf: packageQueries)

        if category.contains("power_transistor") || category.contains("power transistor")
            || category.contains("output transistor") {
            queries.append("\(polarity) power transistor")
            if let power, !power.isEmpty {
                queries.append("\(polarity) power transistor \(power)")
            }
            if let current, !current.isEmpty {
                queries.append("\(polarity) power transistor \(current)")
            }
            for package in packageTerms where package.lowercased().hasPrefix("to") {
                queries.append("\(polarity) power transistor \(package)")
            }
        } else if category.contains("driver_transistor") || category.contains("driver transistor")
            || category.contains("driver stage") {
            queries.append("\(polarity) medium power transistor")
            if let voltage, let current, !voltage.isEmpty, !current.isEmpty {
                queries.append("\(polarity) transistor \(voltage) \(current)")
            }
            for package in packageTerms where package.lowercased().hasPrefix("to") {
                queries.append("\(polarity) medium power transistor \(package)")
            }
        } else if category.contains("low_noise") || category.contains("low noise")
            || category.contains("preamp") {
            queries.append("\(polarity) low noise transistor")
            for package in packageTerms where package.lowercased().hasPrefix("to") {
                queries.append("\(polarity) low noise transistor \(package)")
            }
            queries.append("JFET low noise transistor")
        }

        return uniqueTerms(queries)
    }

    private func normalizedPolarity(from constraints: [String: String]) -> String {
        let polarity = (constraints["polarity"] ?? "").lowercased()
        if polarity.contains("pnp") || polarity.contains("p channel") {
            return "PNP"
        }
        return "NPN"
    }

    private func valueTerms(from constraints: [String: String]) -> [String] {
        [
            "value",
            "resistance",
            "capacitance",
            "inductance",
            "voltage_rating",
            "current_rating",
            "power_rating",
            "tolerance",
            "package",
            "mounting",
            "positions",
            "polarity",
            "contact_form",
            "dielectric",
            "taper",
        ]
            .compactMap { constraints[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map {
                $0
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
            }
            .filter { !$0.isEmpty }
    }

    private func footprintTerms(from footprint: String) -> [String] {
        let normalized = footprint
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        let knownPackages = ["01005", "0201", "0402", "0603", "0805", "1206", "1210", "1812", "sot23", "sot 23", "to 92", "to 220", "to 247", "to 3"]
        return knownPackages.filter { normalized.contains($0) }
    }

    private func packageTerms(from package: String) -> [String] {
        package
            .replacingOccurrences(of: "_or_", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap { token -> [String] in
                let normalized = token.replacingOccurrences(of: "-", with: " ")
                return normalized == token ? [token] : [token, normalized]
            }
    }

    private func roleTerms(from role: String, excluding excluded: Set<String>) -> [String] {
        let stopWords: Set<String> = [
            "for", "and", "the", "with", "stage", "network", "circuit", "path", "supply", "audio",
            "signal", "input", "output", "upper", "lower", "boost", "cut", "tone", "sweepable",
        ]
        return role
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count > 2 && !stopWords.contains(token) && !excluded.contains(token)
            }
    }

    private func pinCount(from requiredPins: String?) -> Int? {
        let pins = requiredPins?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        return pins.isEmpty ? nil : pins.count
    }

    private func numericCount(from value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private func uniqueTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for term in terms {
            let normalized = term.lowercased()
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(term)
        }
        return result
    }
}

struct LiveCatalogQueryCacheEntry: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 6

    var schemaVersion: Int?
    var generatedAt: Date
    var providerID: String
    var query: String
    var candidates: [ComponentCandidate]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case providerID = "provider_id"
        case query
        case candidates
    }
}

struct LiveCatalogRawResponseCacheEntry: Codable, Sendable, Equatable {
    var generatedAt: Date
    var providerID: String
    var query: String
    var requestURL: String?
    var responseBase64: String

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case providerID = "provider_id"
        case query
        case requestURL = "request_url"
        case responseBase64 = "response_base64"
    }
}

struct LiveCatalogQueryCache: Sendable {
    func key(providerID: String, query: String) -> String {
        let input = "\(providerID.lowercased())\n\(query.lowercased())"
        return SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func loadCandidates(
        providerID: String,
        query: String,
        from directory: URL,
        maxAgeSeconds: Int,
        now: Date = Date()
    ) throws -> [ComponentCandidate]? {
        let entryURL = candidatesURL(providerID: providerID, query: query, directory: directory)
        guard FileManager.default.fileExists(atPath: entryURL.path) else { return nil }
        let entry = try JSONDecoder().decode(LiveCatalogQueryCacheEntry.self, from: Data(contentsOf: entryURL))
        guard entry.schemaVersion == LiveCatalogQueryCacheEntry.currentSchemaVersion else {
            return nil
        }
        guard maxAgeSeconds <= 0 || now.timeIntervalSince(entry.generatedAt) <= Double(maxAgeSeconds) else {
            return nil
        }
        return entry.candidates
    }

    func write(
        candidates: [ComponentCandidate],
        rawResponse: Data,
        providerID: String,
        query: String,
        requestURL: URL?,
        to directory: URL,
        now: Date = Date()
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let candidateEntry = LiveCatalogQueryCacheEntry(
            schemaVersion: LiveCatalogQueryCacheEntry.currentSchemaVersion,
            generatedAt: now,
            providerID: providerID,
            query: query,
            candidates: candidates
        )
        try encoder.encode(candidateEntry).write(to: candidatesURL(providerID: providerID, query: query, directory: directory))

        let rawEntry = LiveCatalogRawResponseCacheEntry(
            generatedAt: now,
            providerID: providerID,
            query: query,
            requestURL: requestURL?.absoluteString,
            responseBase64: rawResponse.base64EncodedString()
        )
        try encoder.encode(rawEntry).write(to: rawURL(providerID: providerID, query: query, directory: directory))
    }

    func candidatesURL(providerID: String, query: String, directory: URL) -> URL {
        directory.appendingPathComponent("\(providerID.lowercased())-\(key(providerID: providerID, query: query))-candidates.json")
    }

    func rawURL(providerID: String, query: String, directory: URL) -> URL {
        directory.appendingPathComponent("\(providerID.lowercased())-\(key(providerID: providerID, query: query))-raw.json")
    }
}

struct StaticFixtureCatalogProvider: ComponentCatalogProvider {
    var providerID: String
    var candidates: [ComponentCandidate]

    init(providerID: String = "fixture", candidates: [ComponentCandidate]) {
        self.providerID = providerID
        self.candidates = candidates
    }

    func search(_ request: ComponentSearchRequest) async throws -> [ComponentCandidate] {
        let requestedMPN = request.constraints["mpn"]?.lowercased()
        let requestedPackage = request.constraints["package"]?.lowercased()
        return candidates.filter { candidate in
            if let requestedMPN, candidate.mpn.lowercased() != requestedMPN {
                return false
            }
            if let requestedPackage, candidate.package.lowercased() != requestedPackage {
                return false
            }
            if request.excludedManufacturers.map({ $0.lowercased() }).contains(candidate.manufacturer.lowercased()) {
                return false
            }
            return true
        }
    }
}

struct KiCadLibraryCatalogProvider: ComponentCatalogProvider {
    var providerID: String { "kicad_local" }

    private let symbolsByName: [String: KiCadSymbolDefinition]
    private let footprintsByName: [String: KiCadFootprintDefinition]
    private let footprintSearchEntries: [FootprintSearchEntry]

    private struct FootprintSearchEntry {
        var footprint: KiCadFootprintDefinition
        var text: String
        var compactText: String
    }

    init(symbols: [KiCadSymbolDefinition], footprints: [KiCadFootprintDefinition]) {
        self.symbolsByName = Dictionary(symbols.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.footprintsByName = Dictionary(footprints.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.footprintSearchEntries = footprints.map {
            let text = $0.name.lowercased()
            return FootprintSearchEntry(
                footprint: $0,
                text: text,
                compactText: text.filter { $0.isLetter || $0.isNumber }
            )
        }
    }

    func search(_ request: ComponentSearchRequest) async throws -> [ComponentCandidate] {
        let symbolName = request.constraints["symbol"]
        let symbol = symbolName.flatMap { symbolsByName[$0] }
        let footprintMatches = footprintCandidates(for: request)
        guard symbol != nil || !footprintMatches.isEmpty else {
            return []
        }
        let evidence = [
            symbol.map {
                ComponentEvidence(
                    providerID: providerID,
                    sourceURL: nil,
                    localPath: $0.name,
                    retrievedAt: "local",
                    cachePolicy: "local_library",
                    sha256: nil,
                    extractedParameters: [
                        "symbol": $0.name,
                        "pin_count": "\($0.pins.count)",
                    ],
                    confidence: 1.0,
                    warnings: []
                )
            },
            footprintMatches.first.map {
                let pinPadMap = pinPadMap(for: $0, request: request)
                return ComponentEvidence(
                    providerID: providerID,
                    sourceURL: nil,
                    localPath: $0.name,
                    retrievedAt: "local",
                    cachePolicy: "local_library",
                    sha256: nil,
                    extractedParameters: [
                        "footprint": $0.name,
                        "pad_count": "\(pinPadMap.values.count)",
                    ],
                    confidence: 1.0,
                    warnings: []
                )
            },
        ].compactMap { $0 }
        let footprintCandidates = footprintMatches.prefix(8).map { footprint in
            FootprintCandidate(
                library: libraryName(from: footprint.name),
                name: footprintNameOnly(from: footprint.name),
                packageCompatibilityEvidence: packageCompatibilityEvidence(for: footprint, request: request),
                pinPadMap: pinPadMap(for: footprint, request: request),
                sourceProviderID: providerID,
                sourcePath: footprint.name,
                threeDModel: nil
            )
        }

        return [
            ComponentCandidate(
                mpn: request.constraints["mpn"] ?? "kicad-local-\(symbol?.name ?? footprintMatches.first?.name ?? "asset")",
                manufacturer: request.constraints["manufacturer"] ?? "local_kicad_library",
                normalizedCategory: "kicad_library_asset",
                value: request.constraints["value"],
                package: footprintMatches.first?.name ?? request.constraints["package"] ?? "symbol_only",
                ratings: symbol.map { ["symbol_pin_count": "\($0.pins.count)"] } ?? ["footprint_match_count": "\(footprintMatches.count)"],
                lifecycleState: "library_asset",
                availabilitySummary: "local_library",
                datasheets: [],
                evidence: evidence,
                footprintCandidates: footprintCandidates
            ),
        ]
    }

    private func libraryName(from footprint: String) -> String {
        footprint.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
    }

    private func footprintNameOnly(from footprint: String) -> String {
        let parts = footprint.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 ? parts[1] : footprint
    }

    private func footprintCandidates(for request: ComponentSearchRequest) -> [KiCadFootprintDefinition] {
        if let footprintName = request.constraints["footprint"], let exact = footprintsByName[footprintName] {
            return [exact]
        }
        let packageValues = [
            request.constraints["selected_footprint"],
            request.constraints["package"],
            request.constraints["package_case"],
            request.constraints["case_package"],
            request.constraints["supplier_device_package"],
        ]
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let queryText = ([request.refdes, request.role] + packageValues + Array(request.constraints.values))
            .joined(separator: " ")
            .lowercased()
        let tokens = Set(packageValues.flatMap(packageTokens))
        let category = footprintCategory(for: queryText)
        let requiredPins = requiredPins(from: request.constraints["required_pins"])
        let scored = footprintSearchEntries.compactMap { entry -> (KiCadFootprintDefinition, Int)? in
            let text = entry.text
            let compactText = entry.compactText
            var score = 0
            if !tokens.isEmpty {
                let matched = tokens.filter { text.contains($0) || compactText.contains($0) }
                score += matched.count * 10
            }
            switch category {
            case .resistor:
                guard text.contains("resistor") else { return nil }
                score += 30
            case .capacitor:
                guard text.contains("capacitor") else { return nil }
                score += 30
            case .connector:
                let connectorScore = connectorFootprintScore(
                    text: text,
                    compactText: compactText,
                    queryText: queryText,
                    packageTokens: tokens
                )
                guard connectorScore > 0 else { return nil }
                score += 30 + connectorScore
            case .transistor:
                guard text.contains("package_to") || text.contains("to-") || text.contains("sot") else { return nil }
                score += 25
            case .bridge:
                guard text.contains("diode") || text.contains("bridge") || text.contains("gbu") else { return nil }
                score += 30
            case .potentiometer:
                guard text.contains("potentiometer") || text.contains("pot") else { return nil }
                score += 30
            case .diode:
                guard text.contains("diode") else { return nil }
                score += 25
            case .none:
                break
            }
            if !requiredPins.isEmpty {
                let pinMap = pinPadMap(for: entry.footprint, request: request)
                if requiredPins.allSatisfy({ pinMap[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) {
                    score += 120
                } else if category == .connector {
                    score -= 40
                }
            }
            guard score > 0 else { return nil }
            return (entry.footprint, score)
        }
        return scored.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
        }.map(\.0)
    }

    private func packageTokens(from value: String) -> [String] {
        let ignored: Set<String> = ["package", "case", "pkg", "through", "hole", "tht", "smd", "smt", "lead", "leaded", "to", "free", "hanging", "line", "inline", "mount", "mounted", "panel"]
        var tokens = value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 && !ignored.contains($0) }
        let compact = value.lowercased().filter { $0.isLetter || $0.isNumber }
        if compact.count >= 2, !ignored.contains(compact) {
            tokens.append(compact)
        }
        return tokens
    }

    private func connectorFootprintScore(
        text: String,
        compactText: String,
        queryText: String,
        packageTokens: Set<String>
    ) -> Int {
        guard text.contains("connector") || text.contains("terminal") || text.contains("jack") || text.contains("header") else {
            return 0
        }
        let query = queryText
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let compactQuery = query.filter { $0.isLetter || $0.isNumber }

        if query.contains("terminal block")
            || compactQuery.contains("terminalblock")
            || query.contains("screw terminal") {
            return connectorTextMatchesAny(text, compactText, [
                "terminal",
                "phoenix",
                "screw",
                "bornier",
            ]) ? 80 : 0
        }
        if query.contains("phone audio jack")
            || query.contains("audio jack")
            || query.contains("guitar input")
            || query.contains("phone jack") {
            var score = connectorTextMatchesAny(text, compactText, [
                "connector_audio",
                "audio",
                "jack_6.35",
                "jack635",
                "neutrik",
                "switchcraft",
            ]) ? 80 : 0
            if score > 0, query.contains("guitar"), compactText.contains("jack635") {
                score += 30
            }
            if score > 0, query.contains("guitar"), compactText.contains("jack35") {
                score -= 20
            }
            return score
        }
        if query.contains("speaker connector") || query.contains("speaker output") {
            return connectorTextMatchesAny(text, compactText, [
                "terminal",
                "phoenix",
                "screw",
                "speaker",
                "speakon",
                "banana",
                "binding",
            ]) ? 70 : 0
        }
        if query.contains("barrel") || query.contains("dc power") {
            return connectorTextMatchesAny(text, compactText, [
                "barreljack",
                "barrel",
                "dcjack",
                "dc",
            ]) ? 70 : 0
        }
        if query.contains("coax") || query.contains("rf connector") || query.contains("sma") || query.contains("bnc") {
            return connectorTextMatchesAny(text, compactText, [
                "coaxial",
                "sma",
                "bnc",
                "rf",
            ]) ? 70 : 0
        }
        if query.contains("header") || query.contains("pin header") {
            return connectorTextMatchesAny(text, compactText, [
                "pinheader",
                "header",
                "connector_pin",
            ]) ? 70 : 0
        }

        let matchedPackageTokens = packageTokens.filter { text.contains($0) || compactText.contains($0) }
        return matchedPackageTokens.isEmpty ? 0 : matchedPackageTokens.count * 10
    }

    private func connectorTextMatchesAny(_ text: String, _ compactText: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            let compactNeedle = needle.filter { $0.isLetter || $0.isNumber }
            return text.contains(needle) || (!compactNeedle.isEmpty && compactText.contains(compactNeedle))
        }
    }

    private enum FootprintCategory {
        case resistor
        case capacitor
        case connector
        case transistor
        case bridge
        case potentiometer
        case diode
    }

    private func footprintCategory(for queryText: String) -> FootprintCategory? {
        if queryText.contains("bridge") || queryText.contains("rectifier") { return .bridge }
        if queryText.contains("potentiometer") || queryText.contains("trimmer") { return .potentiometer }
        if queryText.contains("resistor") { return .resistor }
        if queryText.contains("capacitor") { return .capacitor }
        if queryText.contains("connector") || queryText.contains("terminal") || queryText.contains("jack") || queryText.contains("header") {
            return .connector
        }
        if queryText.contains("transistor") || queryText.contains("bjt") || queryText.contains("mosfet") || queryText.contains("jfet") {
            return .transistor
        }
        if queryText.contains("diode") { return .diode }
        return nil
    }

    private func pinPadMap(for footprint: KiCadFootprintDefinition, request: ComponentSearchRequest) -> [String: String] {
        var map = pinPadMap(for: footprint)
        let requiredPins = requiredPins(from: request.constraints["required_pins"])
        guard requiredPins == ["1", "2"] else { return map }
        let query = ([request.refdes, request.role] + Array(request.constraints.values))
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let pads = Set(map.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })

        if (query.contains("phone audio jack")
            || query.contains("audio jack")
            || query.contains("guitar input")
            || query.contains("audio input"))
            && pads.contains("T")
            && pads.contains("S")
            && !pads.contains("R") {
            map["1"] = "T"
            map["2"] = "S"
        }

        if (query.contains("speaker connector")
            || query.contains("speaker output")
            || query.contains("speakon"))
            && pads.contains("1+")
            && pads.contains("1-") {
            map["1"] = "1+"
            map["2"] = "1-"
        }
        return map
    }

    private func pinPadMap(for footprint: KiCadFootprintDefinition) -> [String: String] {
        let entries = footprint.pads.flatMap { pad -> [(String, String)] in
            let number = pad.number.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !number.isEmpty else { return [] }
            let name = pad.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty || name == number {
                return [(number, number)]
            }
            return [
                (name, number),
                (number, number),
            ]
        }
        return Dictionary(entries, uniquingKeysWith: { first, _ in first })
    }

    private func requiredPins(from value: String?) -> [String] {
        value?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func packageCompatibilityEvidence(for footprint: KiCadFootprintDefinition, request: ComponentSearchRequest) -> String {
        if request.constraints["footprint"] == footprint.name {
            return "local KiCad footprint requested by constraint"
        }
        let package = request.constraints["package"] ?? request.constraints["package_case"] ?? request.constraints["case_package"] ?? "unspecified package"
        return "local KiCad footprint matched package/search constraints: \(package)"
    }
}

struct DatasheetEvidenceBuilder: Sendable {
    func metadata(
        manufacturer: String,
        mpn: String,
        url: String,
        localPath: String?,
        providerID: String,
        retrievedAt: String,
        license: String
    ) throws -> DatasheetEvidence {
        let digest = try localPath.map { path in
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }
        return DatasheetEvidence(
            manufacturer: manufacturer,
            mpn: mpn,
            url: url,
            localPath: localPath,
            sha256: digest ?? nil,
            providerID: providerID,
            retrievedAt: retrievedAt,
            license: license,
            citations: []
        )
    }
}

struct DatasheetPDFCache: Sendable {
    struct Entry: Codable, Sendable, Equatable {
        static let currentSchemaVersion = 1

        var schemaVersion: Int
        var manufacturer: String
        var mpn: String
        var url: String
        var providerID: String
        var fileName: String
        var sha256: String
        var byteCount: Int
        var fetchedAt: Date
        var etag: String?
        var lastModified: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case manufacturer
            case mpn
            case url
            case providerID = "provider_id"
            case fileName = "file_name"
            case sha256
            case byteCount = "byte_count"
            case fetchedAt = "fetched_at"
            case etag
            case lastModified = "last_modified"
        }
    }

    func resolve(
        _ evidence: DatasheetEvidence,
        in directory: URL,
        revalidateAfterSeconds: Int,
        transport: any CatalogHTTPTransport = URLSession.shared,
        now: Date = Date()
    ) async throws -> DatasheetEvidence {
        guard let url = URL(string: evidence.url), !evidence.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return evidence
        }
        try FileManager.default.createDirectory(at: pdfDirectory(in: directory), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifestDirectory(in: directory), withIntermediateDirectories: true)

        if let cached = try loadEntry(for: evidence, from: directory),
           FileManager.default.fileExists(atPath: pdfURL(for: cached, in: directory).path) {
            let cachedEvidence = evidenceWithLocalPDF(evidence, entry: cached, directory: directory, cachePolicy: "datasheet_pdf_cache")
            guard shouldRevalidate(cached, now: now, revalidateAfterSeconds: revalidateAfterSeconds) else {
                return cachedEvidence
            }
            if let refreshed = try await revalidatedEvidence(
                evidence,
                cached: cached,
                url: url,
                directory: directory,
                transport: transport,
                now: now
            ) {
                return refreshed
            }
            return cachedEvidence
        }

        let request = URLRequest(url: url, timeoutInterval: 30)
        let (data, response) = try await transport.data(for: request)
        return try writeDownloadedEvidence(
            evidence,
            data: data,
            response: response,
            directory: directory,
            now: now
        )
    }

    func loadLocal(
        _ evidence: DatasheetEvidence,
        from directory: URL
    ) throws -> DatasheetEvidence? {
        guard let cached = try loadEntry(for: evidence, from: directory),
              FileManager.default.fileExists(atPath: pdfURL(for: cached, in: directory).path) else {
            return nil
        }
        return evidenceWithLocalPDF(evidence, entry: cached, directory: directory, cachePolicy: "datasheet_pdf_cache")
    }

    private func revalidatedEvidence(
        _ evidence: DatasheetEvidence,
        cached: Entry,
        url: URL,
        directory: URL,
        transport: any CatalogHTTPTransport,
        now: Date
    ) async throws -> DatasheetEvidence? {
        var request = URLRequest(url: url, timeoutInterval: 30)
        if let etag = cached.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = cached.lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        let (data, response) = try await transport.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 304 {
            var updated = cached
            updated.fetchedAt = now
            try writeEntry(updated, to: directory)
            return evidenceWithLocalPDF(evidence, entry: updated, directory: directory, cachePolicy: "datasheet_pdf_cache")
        }
        return try writeDownloadedEvidence(
            evidence,
            data: data,
            response: response,
            directory: directory,
            now: now,
            existingFileName: cached.fileName
        )
    }

    private func writeDownloadedEvidence(
        _ evidence: DatasheetEvidence,
        data: Data,
        response: URLResponse,
        directory: URL,
        now: Date,
        existingFileName: String? = nil
    ) throws -> DatasheetEvidence {
        if let http = response as? HTTPURLResponse {
            guard (200...299).contains(http.statusCode) else {
                throw LiveCatalogProviderError.httpStatus(http.statusCode)
            }
        }
        let fileName = existingFileName ?? "\(key(for: evidence)).pdf"
        let fileURL = pdfDirectory(in: directory).appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        let entry = Entry(
            schemaVersion: Entry.currentSchemaVersion,
            manufacturer: evidence.manufacturer,
            mpn: evidence.mpn,
            url: evidence.url,
            providerID: evidence.providerID,
            fileName: fileName,
            sha256: sha256(data),
            byteCount: data.count,
            fetchedAt: now,
            etag: header("ETag", from: response),
            lastModified: header("Last-Modified", from: response)
        )
        try writeEntry(entry, to: directory)
        return evidenceWithLocalPDF(evidence, entry: entry, directory: directory, cachePolicy: "datasheet_pdf_cache")
    }

    private func shouldRevalidate(_ entry: Entry, now: Date, revalidateAfterSeconds: Int) -> Bool {
        guard revalidateAfterSeconds > 0 else { return false }
        return now.timeIntervalSince(entry.fetchedAt) >= Double(revalidateAfterSeconds)
    }

    private func loadEntry(for evidence: DatasheetEvidence, from directory: URL) throws -> Entry? {
        let url = manifestURL(for: evidence, in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: url))
        guard entry.schemaVersion == Entry.currentSchemaVersion else { return nil }
        return entry
    }

    private func writeEntry(_ entry: Entry, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entry).write(to: manifestURL(forKey: key(providerID: entry.providerID, manufacturer: entry.manufacturer, mpn: entry.mpn, url: entry.url), in: directory))
    }

    private func evidenceWithLocalPDF(
        _ evidence: DatasheetEvidence,
        entry: Entry,
        directory: URL,
        cachePolicy: String
    ) -> DatasheetEvidence {
        var evidence = evidence
        evidence.localPath = pdfURL(for: entry, in: directory).path
        evidence.sha256 = entry.sha256
        evidence.license = [evidence.license, cachePolicy]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ";")
        return evidence
    }

    private func manifestURL(for evidence: DatasheetEvidence, in directory: URL) -> URL {
        manifestURL(forKey: key(for: evidence), in: directory)
    }

    private func manifestURL(forKey key: String, in directory: URL) -> URL {
        manifestDirectory(in: directory).appendingPathComponent("\(key).json")
    }

    private func pdfURL(for entry: Entry, in directory: URL) -> URL {
        pdfDirectory(in: directory).appendingPathComponent(entry.fileName)
    }

    private func manifestDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("manifest", isDirectory: true)
    }

    private func pdfDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("pdf", isDirectory: true)
    }

    private func key(for evidence: DatasheetEvidence) -> String {
        key(providerID: evidence.providerID, manufacturer: evidence.manufacturer, mpn: evidence.mpn, url: evidence.url)
    }

    private func key(providerID: String, manufacturer: String, mpn: String, url: String) -> String {
        let input = [providerID, manufacturer, mpn, url]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "\n")
        return sha256(Data(input.utf8))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func header(_ name: String, from response: URLResponse) -> String? {
        guard let http = response as? HTTPURLResponse else { return nil }
        let target = name.lowercased()
        for (key, value) in http.allHeaderFields {
            guard String(describing: key).lowercased() == target else { continue }
            let string = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            return string.isEmpty ? nil : string
        }
        return nil
    }
}

struct DigiKeyCatalogProviderAdapter: Sendable {
    let providerID = "digikey"

    func mapRecordedResponse(_ data: Data) throws -> [ComponentCandidate] {
        let object = try CatalogFixtureJSON.object(data)
        let products = object["Products"] as? [[String: Any]] ?? []
        return products.map { product in
            let manufacturer = CatalogFixtureJSON.string(product["Manufacturer"] as? [String: Any], "Name")
            let mpn = CatalogFixtureJSON.string(product, "ManufacturerProductNumber")
            let parameters = CatalogFixtureJSON.parameterMap(
                product["Parameters"] as? [[String: Any]],
                nameKey: "ParameterText",
                valueKey: "ValueText"
            )
            let descriptionObject = product["Description"] as? [String: Any]
            let productDescription = CatalogFixtureJSON.firstNonEmpty([
                CatalogFixtureJSON.string(product, "ProductDescription"),
                CatalogFixtureJSON.string(descriptionObject, "ProductDescription"),
                CatalogFixtureJSON.string(descriptionObject, "DetailedDescription"),
            ])
            let categoryName = CatalogFixtureJSON.categoryName(product["Category"] as? [String: Any])
            let package = CatalogFixtureJSON.packageEvidence(
                parameters,
                category: categoryName,
                description: productDescription
            )
            let ratings = CatalogFixtureJSON.normalizedWithDescription(parameters, description: productDescription)
            return ComponentCandidate(
                mpn: mpn,
                manufacturer: manufacturer,
                normalizedCategory: CatalogFixtureJSON.normalizedKey(CatalogFixtureJSON.firstNonEmpty([
                    categoryName,
                    productDescription,
                ])),
                value: productDescription.isEmpty ? nil : productDescription,
                package: package,
                ratings: ratings,
                lifecycleState: CatalogFixtureJSON.firstNonEmpty([
                    CatalogFixtureJSON.string(product, "LifecycleStatus"),
                    CatalogFixtureJSON.string(product, "ProductStatus"),
                    "unknown",
                ]),
                availabilitySummary: "\(CatalogFixtureJSON.int(product, "QuantityAvailable")) available",
                datasheets: [
                    DatasheetEvidence(
                        manufacturer: manufacturer,
                        mpn: mpn,
                        url: CatalogFixtureJSON.string(product, "DatasheetUrl"),
                        localPath: nil,
                        sha256: nil,
                        providerID: providerID,
                        retrievedAt: "recorded_fixture",
                        license: "recorded_fixture",
                        citations: []
                    ),
                ].filter { !$0.url.isEmpty },
                evidence: [
                    ComponentEvidence(
                        providerID: providerID,
                        sourceURL: CatalogFixtureJSON.optionalString(product, "ProductUrl"),
                        localPath: nil,
                        retrievedAt: "recorded_fixture",
                        cachePolicy: "recorded_fixture",
                        sha256: nil,
                        extractedParameters: ratings.merging(["package": package]) { first, _ in first },
                        confidence: 1.0,
                        warnings: []
                    ),
                ],
                footprintCandidates: []
            )
        }
    }
}

struct MouserCatalogProviderAdapter: Sendable {
    let providerID = "mouser"

    func mapRecordedResponse(_ data: Data) throws -> [ComponentCandidate] {
        let object = try CatalogFixtureJSON.object(data)
        let searchResults = object["SearchResults"] as? [String: Any]
        let parts = searchResults?["Parts"] as? [[String: Any]] ?? []
        return parts.map { part in
            let manufacturer = CatalogFixtureJSON.string(part, "Manufacturer")
            let mpn = CatalogFixtureJSON.string(part, "ManufacturerPartNumber")
            let attributes = CatalogFixtureJSON.parameterMap(
                part["ProductAttributes"] as? [[String: Any]],
                nameKey: "AttributeName",
                valueKey: "AttributeValue"
            )
            let description = CatalogFixtureJSON.string(part, "Description")
            let category = CatalogFixtureJSON.string(part, "Category")
            let packageFields = [
                "Package": CatalogFixtureJSON.string(part, "Package"),
                "Package / Case": CatalogFixtureJSON.string(part, "PackageCase"),
                "Package Type": CatalogFixtureJSON.string(part, "PackageType"),
                "Supplier Device Package": CatalogFixtureJSON.string(part, "SupplierDevicePackage"),
            ].filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let evidenceAttributes = attributes.merging(packageFields) { current, _ in current }
            let package = CatalogFixtureJSON.packageEvidence(
                evidenceAttributes,
                category: category,
                description: description
            )
            let ratings = CatalogFixtureJSON.normalizedWithDescription(evidenceAttributes, description: description)
            let datasheetURL = CatalogFixtureJSON.firstNonEmpty([
                CatalogFixtureJSON.string(part, "DataSheetUrl"),
                CatalogFixtureJSON.string(part, "DatasheetUrl"),
                CatalogFixtureJSON.string(part, "DatasheetURL"),
                CatalogFixtureJSON.string(part, "DataSheetURL"),
            ])
            return ComponentCandidate(
                mpn: mpn,
                manufacturer: manufacturer,
                normalizedCategory: CatalogFixtureJSON.normalizedKey(CatalogFixtureJSON.string(part, "Category")),
                value: description.isEmpty ? nil : description,
                package: package,
                ratings: ratings,
                lifecycleState: CatalogFixtureJSON.string(part, "LifecycleStatus", defaultValue: "unknown"),
                availabilitySummary: CatalogFixtureJSON.string(part, "Availability", defaultValue: "unknown"),
                datasheets: [
                    DatasheetEvidence(
                        manufacturer: manufacturer,
                        mpn: mpn,
                        url: datasheetURL,
                        localPath: nil,
                        sha256: nil,
                        providerID: providerID,
                        retrievedAt: "recorded_fixture",
                        license: "recorded_fixture",
                        citations: []
                    ),
                ].filter { !$0.url.isEmpty },
                evidence: [
                    ComponentEvidence(
                        providerID: providerID,
                        sourceURL: CatalogFixtureJSON.optionalString(part, "ProductDetailUrl"),
                        localPath: nil,
                        retrievedAt: "recorded_fixture",
                        cachePolicy: "recorded_fixture",
                        sha256: nil,
                        extractedParameters: ratings.merging(["package": package]) { first, _ in first },
                        confidence: 1.0,
                        warnings: []
                    ),
                ],
                footprintCandidates: []
            )
        }
    }
}

struct AggregatorCatalogProviderAdapter: Sendable {
    var providerID: String

    init(providerID: String) {
        self.providerID = providerID
    }

    func mapRecordedResponse(_ data: Data) throws -> [ComponentCandidate] {
        let object = try CatalogFixtureJSON.object(data)
        let parts = object["parts"] as? [[String: Any]] ?? []
        return parts.map { part in
            let manufacturer = CatalogFixtureJSON.string(part, "manufacturer")
            let mpn = CatalogFixtureJSON.string(part, "mpn")
            let specs = part["specs"] as? [String: Any] ?? [:]
            let ratings = specs.reduce(into: [String: String]()) { result, entry in
                result[CatalogFixtureJSON.normalizedKey(entry.key)] = "\(entry.value)"
            }
            return ComponentCandidate(
                mpn: mpn,
                manufacturer: manufacturer,
                normalizedCategory: CatalogFixtureJSON.normalizedKey(CatalogFixtureJSON.string(part, "category")),
                value: CatalogFixtureJSON.optionalString(part, "description"),
                package: CatalogFixtureJSON.string(part, "package"),
                ratings: ratings,
                lifecycleState: CatalogFixtureJSON.string(part, "lifecycle", defaultValue: "unknown"),
                availabilitySummary: CatalogFixtureJSON.string(part, "availability", defaultValue: "unknown"),
                datasheets: [
                    DatasheetEvidence(
                        manufacturer: manufacturer,
                        mpn: mpn,
                        url: CatalogFixtureJSON.string(part, "datasheet_url"),
                        localPath: nil,
                        sha256: nil,
                        providerID: providerID,
                        retrievedAt: "recorded_fixture",
                        license: "recorded_fixture",
                        citations: []
                    ),
                ].filter { !$0.url.isEmpty },
                evidence: [
                    ComponentEvidence(
                        providerID: providerID,
                        sourceURL: CatalogFixtureJSON.optionalString(part, "source_url"),
                        localPath: nil,
                        retrievedAt: "recorded_fixture",
                        cachePolicy: "recorded_fixture",
                        sha256: nil,
                        extractedParameters: ratings,
                        confidence: 1.0,
                        warnings: []
                    ),
                ],
                footprintCandidates: []
            )
        }
    }
}

struct VendorFeedCatalogProviderAdapter: Sendable {
    let providerID = "vendor_feed"

    func mapRecordedResponse(_ data: Data) throws -> [ComponentCandidate] {
        if let object = try? CatalogFixtureJSON.object(data) {
            return mapJSON(object)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected UTF-8 CSV or JSON vendor feed."))
        }
        return try mapCSV(text)
    }

    private func mapJSON(_ object: [String: Any]) -> [ComponentCandidate] {
        let parts = objects(forAnyKey: ["parts", "Parts", "products", "Products", "items", "Items"], in: object)
        return parts.map { candidate(from: flattenJSONPart($0)) }
    }

    private func mapCSV(_ text: String) throws -> [ComponentCandidate] {
        let rows = parseCSV(text).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard let header = rows.first else { return [] }
        let keys = header.map(normalizedHeader)
        return rows.dropFirst().map { row in
            var fields: [String: String] = [:]
            for index in keys.indices {
                guard !keys[index].isEmpty, index < row.count else { continue }
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    fields[keys[index]] = value
                }
            }
            return candidate(from: fields)
        }
    }

    private func candidate(from fields: [String: String]) -> ComponentCandidate {
        let manufacturer = first(fields, ["manufacturer", "mfr", "manufacturer_name", "mfg"])
        let mpn = first(fields, ["mpn", "manufacturer_part_number", "manufacturer_product_number", "part_number"])
        let description = first(fields, ["description", "product_description", "detailed_description"])
        let category = first(fields, ["category", "product_category", "normalized_category"])
        let package = CatalogFixtureJSON.firstNonEmpty([
            first(fields, ["package", "package_case", "package_type", "case", "mounting_type"]),
            CatalogFixtureJSON.packageEvidence(fields, category: category, description: description),
        ])
        let ratings = normalizedVendorRatings(fields, description: description)
        let distributor = first(fields, ["distributor", "supplier", "seller", "vendor"])
        let availability = availabilitySummary(fields: fields, distributor: distributor)
        return ComponentCandidate(
            mpn: mpn,
            manufacturer: manufacturer,
            normalizedCategory: CatalogFixtureJSON.normalizedKey(category),
            value: description.isEmpty ? nil : description,
            package: package,
            ratings: ratings,
            lifecycleState: CatalogFixtureJSON.firstNonEmpty([first(fields, ["lifecycle", "lifecycle_status", "product_status"]), "unknown"]),
            availabilitySummary: availability,
            datasheets: datasheets(from: fields, manufacturer: manufacturer, mpn: mpn),
            evidence: [
                ComponentEvidence(
                    providerID: providerID,
                    sourceURL: optional(first(fields, ["source_url", "product_url", "product_detail_url", "buy_url", "url"])),
                    localPath: nil,
                    retrievedAt: "user_supplied_feed",
                    cachePolicy: "user_supplied_feed",
                    sha256: nil,
                    extractedParameters: ratings.merging([
                        "description": description,
                        "package": package,
                        "availability": availability,
                        "distributor": distributor,
                    ]) { current, _ in current },
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: []
        )
    }

    private func flattenJSONPart(_ part: [String: Any]) -> [String: String] {
        var fields: [String: String] = [:]
        for (key, value) in part {
            let normalized = normalizedHeader(key)
            if let string = value as? String {
                fields[normalized] = string
            } else if let number = value as? NSNumber {
                fields[normalized] = number.stringValue
            } else if let dictionary = value as? [String: Any] {
                if normalized == "ratings" || normalized == "specs" || normalized == "parameters" {
                    for (ratingKey, ratingValue) in dictionary {
                        fields[normalizedHeader(ratingKey)] = "\(ratingValue)"
                    }
                } else if let name = dictionary["name"] as? String {
                    fields[normalized] = name
                }
            }
        }
        return fields
    }

    private func normalizedVendorRatings(_ fields: [String: String], description: String) -> [String: String] {
        var result = CatalogFixtureJSON.normalizedWithDescription(fields, description: description)
        let source = result
        copyFirstPresent(in: source, to: &result, target: "voltage_v", keys: [
            "voltage",
            "voltage_rating",
            "vce",
            "collector_emitter_breakdown_voltage",
            "voltage_v",
        ])
        copyFirstPresent(in: source, to: &result, target: "current_a", keys: [
            "current",
            "current_rating",
            "ic",
            "collector_current",
            "current_a",
        ])
        copyFirstPresent(in: source, to: &result, target: "power_w", keys: [
            "power",
            "power_rating",
            "power_max",
            "power_dissipation",
            "power_w",
        ])
        copyFirstPresent(in: source, to: &result, target: "moq", keys: [
            "moq",
            "minimum_order_quantity",
            "min_order_qty",
        ])
        copyFirstPresent(in: source, to: &result, target: "lead_time", keys: [
            "lead_time",
            "factory_lead_time",
        ])
        return result
    }

    private func availabilitySummary(fields: [String: String], distributor: String) -> String {
        let availability = first(fields, ["availability", "quantity_available", "stock", "inventory", "qty_available"])
        guard !availability.isEmpty else { return "unknown" }
        return distributor.isEmpty ? availability : "\(distributor): \(availability)"
    }

    private func datasheets(from fields: [String: String], manufacturer: String, mpn: String) -> [DatasheetEvidence] {
        let urls = uniqueValues([
            first(fields, ["datasheet_url", "data_sheet_url", "datasheet", "document_url"]),
        ])
        return urls.map { url in
            DatasheetEvidence(
                manufacturer: manufacturer,
                mpn: mpn,
                url: url,
                localPath: nil,
                sha256: nil,
                providerID: providerID,
                retrievedAt: "user_supplied_feed",
                license: "user_supplied_feed",
                citations: []
            )
        }
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\n", !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private func normalizedHeader(_ value: String) -> String {
        CatalogFixtureJSON.normalizedKey(value)
            .replacingOccurrences(of: "_url", with: "_url")
    }

    private func first(_ fields: [String: String], _ keys: [String]) -> String {
        for key in keys {
            if let value = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func optional(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private func objects(forAnyKey keys: [String], in object: [String: Any]) -> [[String: Any]] {
        for key in keys {
            guard let value = object[key] else { continue }
            if let rows = value as? [[String: Any]] { return rows }
            if let row = value as? [String: Any] { return [row] }
        }
        return []
    }

    private func copyFirstPresent(in source: [String: String], to result: inout [String: String], target: String, keys: [String]) {
        let value = first(source, keys)
        if !value.isEmpty {
            let current = result[target]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current.isEmpty || (!containsUnitLikeText(current) && containsUnitLikeText(value)) {
                result[target] = value
            }
        }
    }

    private func containsUnitLikeText(_ value: String) -> Bool {
        value.contains { $0.isLetter || $0 == "%" || $0 == "Ω" || $0 == "µ" }
    }
}

struct NexarCatalogProviderAdapter: Sendable {
    let providerID = "nexar"

    func mapRecordedResponse(_ data: Data) throws -> [ComponentCandidate] {
        let object = try CatalogFixtureJSON.object(data)
        if let errors = object["errors"] as? [[String: Any]], !errors.isEmpty {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: CatalogFixtureJSON.string(errors.first, "message", defaultValue: "Nexar GraphQL returned errors.")
            ))
        }
        let dataObject = object["data"] as? [String: Any] ?? object
        let searchObject = (dataObject["supSearchMpn"] as? [String: Any])
            ?? (dataObject["supSearch"] as? [String: Any])

        if let results = searchObject?["results"] as? [[String: Any]] {
            return results.compactMap { result in
                guard let part = result["part"] as? [String: Any] else { return nil }
                return candidate(from: part, resultDescription: CatalogFixtureJSON.optionalString(result, "description"))
            }
        }
        if let multiMatch = dataObject["supMultiMatch"] as? [String: Any],
           let parts = multiMatch["parts"] as? [[String: Any]] {
            return parts.map { candidate(from: $0, resultDescription: nil) }
        }
        return []
    }

    private func candidate(from part: [String: Any], resultDescription: String?) -> ComponentCandidate {
        let manufacturerObject = part["manufacturer"] as? [String: Any]
        let categoryObject = part["category"] as? [String: Any]
        let manufacturer = CatalogFixtureJSON.string(manufacturerObject, "name")
        let mpn = CatalogFixtureJSON.string(part, "mpn")
        let specs = specMap(from: part["specs"] as? [[String: Any]])
        let description = resultDescription ?? CatalogFixtureJSON.string(part, "shortDescription")
        let ratings = normalizedNexarRatings(
            CatalogFixtureJSON.normalizedWithDescription(specs, description: description)
        )
        let package = firstPresent(
            in: ratings,
            keys: ["package_case", "package", "case_package", "supplier_device_package", "mounting_type"]
        )
        let lifecycle = firstPresent(
            in: ratings,
            keys: ["lifecycle_status", "lifecyclestatus", "manufacturer_lifecycle_status"]
        )
        let sourceURL = CatalogFixtureJSON.optionalString(part, "octopartUrl")
            ?? CatalogFixtureJSON.optionalString(part, "url")
            ?? CatalogFixtureJSON.optionalString(manufacturerObject ?? [:], "homepageUrl")
        let datasheets = datasheets(from: part, manufacturer: manufacturer, mpn: mpn)
        return ComponentCandidate(
            mpn: mpn,
            manufacturer: manufacturer,
            normalizedCategory: CatalogFixtureJSON.normalizedKey(CatalogFixtureJSON.string(categoryObject, "name")),
            value: nil,
            package: package,
            ratings: ratings,
            lifecycleState: lifecycle.isEmpty ? "unknown" : lifecycle,
            availabilitySummary: availabilitySummary(from: part),
            datasheets: datasheets,
            evidence: [
                ComponentEvidence(
                    providerID: providerID,
                    sourceURL: sourceURL,
                    localPath: nil,
                    retrievedAt: "recorded_fixture",
                    cachePolicy: "recorded_fixture",
                    sha256: nil,
                    extractedParameters: ratings.merging([
                        "name": CatalogFixtureJSON.string(part, "name"),
                        "description": description,
                        "package": package,
                    ]) { first, _ in first },
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: []
        )
    }

    private func normalizedNexarRatings(_ ratings: [String: String]) -> [String: String] {
        var result = ratings
        copyFirstPresent(in: ratings, to: &result, target: "voltage_v", keys: [
            "vce",
            "voltage_collector_emitter_breakdown_max",
            "voltage_collector_emitter_breakdown",
            "collector_emitter_breakdown_voltage",
            "voltage_rating",
            "voltage",
        ])
        copyFirstPresent(in: ratings, to: &result, target: "current_a", keys: [
            "ic",
            "current_collector_ic_max",
            "current_collector_max",
            "collector_current",
            "current_rating",
            "current",
        ])
        copyFirstPresent(in: ratings, to: &result, target: "power_w", keys: [
            "power_max",
            "power_dissipation",
            "power_rating",
            "power",
        ])
        copyFirstPresent(in: ratings, to: &result, target: "polarity", keys: [
            "transistor_polarity",
            "polarity",
        ])
        return result
    }

    private func copyFirstPresent(
        in source: [String: String],
        to result: inout [String: String],
        target: String,
        keys: [String]
    ) {
        guard result[target]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else {
            return
        }
        for key in keys {
            guard let value = source[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            result[target] = value
            return
        }
    }

    private func specMap(from specs: [[String: Any]]?) -> [String: String] {
        (specs ?? []).reduce(into: [String: String]()) { result, spec in
            let attribute = spec["attribute"] as? [String: Any]
            let name = CatalogFixtureJSON.string(attribute, "shortname").isEmpty
                ? CatalogFixtureJSON.string(attribute, "name")
                : CatalogFixtureJSON.string(attribute, "shortname")
            guard !name.isEmpty else { return }
            let displayValue = CatalogFixtureJSON.string(spec, "displayValue")
            let rawValue = CatalogFixtureJSON.string(spec, "value")
            let units = CatalogFixtureJSON.string(spec, "unitsSymbol").isEmpty
                ? CatalogFixtureJSON.string(spec, "unitsName")
                : CatalogFixtureJSON.string(spec, "unitsSymbol")
            let value = !displayValue.isEmpty
                ? displayValue
                : [rawValue, units].filter { !$0.isEmpty }.joined(separator: " ")
            if !value.isEmpty {
                result[name] = value
            }
        }
    }

    private func datasheets(from part: [String: Any], manufacturer: String, mpn: String) -> [DatasheetEvidence] {
        var urls: [String] = []
        if let best = part["bestDatasheet"] as? [String: Any],
           let url = CatalogFixtureJSON.optionalString(best, "url") {
            urls.append(url)
        }
        let collections = part["documentCollections"] as? [[String: Any]] ?? []
        for collection in collections {
            for document in collection["documents"] as? [[String: Any]] ?? [] {
                guard let url = CatalogFixtureJSON.optionalString(document, "url") else { continue }
                urls.append(url)
            }
        }
        return uniqueValues(urls).map { url in
            DatasheetEvidence(
                manufacturer: manufacturer,
                mpn: mpn,
                url: url,
                localPath: nil,
                sha256: nil,
                providerID: providerID,
                retrievedAt: "recorded_fixture",
                license: "recorded_fixture",
                citations: []
            )
        }
    }

    private func availabilitySummary(from part: [String: Any]) -> String {
        if let total = part["totalAvail"] as? Int {
            return "\(total) total available"
        }
        if let total = part["totalAvail"] as? NSNumber {
            return "\(total.intValue) total available"
        }
        let sellers = part["sellers"] as? [[String: Any]] ?? []
        let sellerSummaries = sellers.compactMap { seller -> String? in
            guard let company = seller["company"] as? [String: Any] else { return nil }
            let name = CatalogFixtureJSON.string(company, "name")
            let inventory = (seller["offers"] as? [[String: Any]] ?? [])
                .compactMap { offer -> Int? in
                    if let value = offer["inventoryLevel"] as? Int { return value }
                    if let value = offer["inventoryLevel"] as? NSNumber { return value.intValue }
                    return nil
                }
                .reduce(0, +)
            guard !name.isEmpty else { return nil }
            return inventory > 0 ? "\(name): \(inventory)" : name
        }
        return sellerSummaries.isEmpty ? "unknown" : sellerSummaries.joined(separator: "; ")
    }

    private func firstPresent(in values: [String: String], keys: [String]) -> String {
        for key in keys {
            if let value = values[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return ""
    }
}

struct TrustedPartsCatalogProviderAdapter: Sendable {
    let providerID = "trustedparts"

    func mapRecordedResponse(_ data: Data) throws -> [ComponentCandidate] {
        let object = try CatalogFixtureJSON.object(data)
        return partObjects(from: object).map(candidate(from:)).filter {
            !$0.mpn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func partObjects(from object: [String: Any]) -> [[String: Any]] {
        let resultRows = objects(forAnyKey: ["Results", "results", "SearchResults", "searchResults"], in: object)
        let nestedParts = resultRows.flatMap { row in
            let parts = objects(forAnyKey: ["Parts", "parts", "Items", "items", "Products", "products"], in: row)
            return parts.isEmpty ? [row] : parts
        }
        if !nestedParts.isEmpty { return nestedParts }
        return objects(forAnyKey: ["Parts", "parts", "Items", "items", "Products", "products"], in: object)
    }

    private func candidate(from part: [String: Any]) -> ComponentCandidate {
        let manufacturer = string(part, keys: [
            "Manufacturer",
            "manufacturer",
            "ManufacturerName",
            "manufacturerName",
            "Mfr",
            "mfr",
        ], nestedKeys: ["Name", "name"])
        let mpn = string(part, keys: [
            "ManufacturerPartNumber",
            "manufacturerPartNumber",
            "ManufacturerProductNumber",
            "manufacturerProductNumber",
            "PartNumber",
            "partNumber",
            "Mpn",
            "MPN",
            "mpn",
        ])
        let description = string(part, keys: [
            "Description",
            "description",
            "ProductDescription",
            "productDescription",
            "DetailedDescription",
            "detailedDescription",
        ])
        let category = string(part, keys: ["Category", "category", "ProductCategory", "productCategory"], nestedKeys: ["Name", "name"])
        let parameterMap = parameterMap(from: part)
        var ratings = normalizedTrustedPartsRatings(CatalogFixtureJSON.normalizedWithDescription(parameterMap, description: description))
        let offers = offerObjects(from: part)
        ratings.merge(offerRatings(from: offers)) { current, _ in current }
        let package = CatalogFixtureJSON.firstNonEmpty([
            string(part, keys: ["Package", "package", "PackageType", "packageType", "PackageCase", "packageCase"]),
            firstPresent(in: ratings, keys: [
                "package_case",
                "package",
                "supplier_device_package",
                "mounting_type",
                "termination",
            ]),
            CatalogFixtureJSON.packageEvidence(parameterMap, category: category, description: description),
        ])
        let sourceURL = string(part, keys: [
            "ProductUrl",
            "ProductURL",
            "productUrl",
            "ProductDetailUrl",
            "productDetailUrl",
            "BuyUrl",
            "BuyURL",
            "buyUrl",
        ])

        return ComponentCandidate(
            mpn: mpn,
            manufacturer: manufacturer,
            normalizedCategory: CatalogFixtureJSON.normalizedKey(category),
            value: description.isEmpty ? nil : description,
            package: package,
            ratings: ratings,
            lifecycleState: CatalogFixtureJSON.firstNonEmpty([
                string(part, keys: ["LifecycleStatus", "lifecycleStatus", "LifeCycleStatus", "ProductStatus", "productStatus"]),
                "unknown",
            ]),
            availabilitySummary: availabilitySummary(from: part, offers: offers),
            datasheets: datasheets(from: part, manufacturer: manufacturer, mpn: mpn),
            evidence: [
                ComponentEvidence(
                    providerID: providerID,
                    sourceURL: sourceURL.isEmpty ? nil : sourceURL,
                    localPath: nil,
                    retrievedAt: "recorded_fixture",
                    cachePolicy: "recorded_fixture",
                    sha256: nil,
                    extractedParameters: ratings.merging([
                        "description": description,
                        "package": package,
                        "availability": availabilitySummary(from: part, offers: offers),
                    ]) { current, _ in current },
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: []
        )
    }

    private func datasheets(from part: [String: Any], manufacturer: String, mpn: String) -> [DatasheetEvidence] {
        let directURLs = [
            string(part, keys: ["DatasheetUrl", "DataSheetUrl", "DatasheetURL", "datasheetUrl", "datasheetURL"]),
            string(part, keys: ["Datasheet", "datasheet"], nestedKeys: ["Url", "URL", "url"]),
        ]
        let documentURLs = objects(forAnyKey: ["Documents", "documents", "Datasheets", "datasheets"], in: part)
            .map { string($0, keys: ["Url", "URL", "url", "DatasheetUrl", "datasheetUrl"]) }
        return uniqueValues(directURLs + documentURLs).map { url in
            DatasheetEvidence(
                manufacturer: manufacturer,
                mpn: mpn,
                url: url,
                localPath: nil,
                sha256: nil,
                providerID: providerID,
                retrievedAt: "recorded_fixture",
                license: "recorded_fixture",
                citations: []
            )
        }
    }

    private func availabilitySummary(from part: [String: Any], offers: [[String: Any]]) -> String {
        let direct = string(part, keys: ["Availability", "availability", "Stock", "stock"])
        if !direct.isEmpty { return direct }
        let quantity = int(part, keys: ["QuantityAvailable", "quantityAvailable", "TotalAvailable", "totalAvailable"])
        if quantity > 0 { return "\(quantity) total available" }
        let summaries = offers.compactMap { offer -> String? in
            let distributor = string(offer, keys: [
                "Distributor",
                "distributor",
                "Supplier",
                "supplier",
                "Seller",
                "seller",
                "Company",
                "company",
            ], nestedKeys: ["Name", "name"])
            guard !distributor.isEmpty else { return nil }
            let quantity = int(offer, keys: [
                "QuantityAvailable",
                "quantityAvailable",
                "Inventory",
                "inventory",
                "Stock",
                "stock",
                "Available",
                "available",
                "inventoryLevel",
            ])
            return quantity > 0 ? "\(distributor): \(quantity)" : distributor
        }
        return summaries.isEmpty ? "unknown" : summaries.joined(separator: "; ")
    }

    private func offerRatings(from offers: [[String: Any]]) -> [String: String] {
        var ratings: [String: String] = [:]
        for offer in offers {
            copyFirstPresent(from: offer, to: &ratings, target: "packaging", keys: ["Packaging", "packaging"])
            copyFirstPresent(from: offer, to: &ratings, target: "moq", keys: ["Moq", "MOQ", "moq", "MinimumOrderQuantity"])
            copyFirstPresent(from: offer, to: &ratings, target: "lead_time", keys: ["LeadTime", "leadTime", "FactoryLeadTime"])
            copyFirstPresent(from: offer, to: &ratings, target: "source", keys: ["Distributor", "Supplier", "Seller"])
        }
        return ratings
    }

    private func parameterMap(from part: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        let rows = objects(forAnyKey: ["Parameters", "parameters", "ProductAttributes", "productAttributes", "Attributes", "attributes", "Specs", "specs"], in: part)
        for row in rows {
            let name = string(row, keys: [
                "Name",
                "name",
                "ParameterText",
                "parameterText",
                "ParameterName",
                "parameterName",
                "AttributeName",
                "attributeName",
                "shortname",
            ])
            let value = string(row, keys: [
                "Value",
                "value",
                "ValueText",
                "valueText",
                "ParameterValue",
                "parameterValue",
                "AttributeValue",
                "attributeValue",
                "DisplayValue",
                "displayValue",
            ])
            if !name.isEmpty, !value.isEmpty {
                result[name] = value
            }
        }
        for key in ["Package", "PackageType", "Packaging", "Voltage", "Current", "Power", "Tolerance", "Resistance", "Capacitance"] {
            let value = string(part, keys: [key, key.prefix(1).lowercased() + key.dropFirst()])
            if !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    private func normalizedTrustedPartsRatings(_ ratings: [String: String]) -> [String: String] {
        var result = ratings
        copyFirstPresent(in: ratings, to: &result, target: "voltage_v", keys: [
            "voltage_collector_emitter_breakdown_max",
            "voltage_collector_emitter_breakdown",
            "collector_emitter_breakdown_voltage",
            "voltage_rating",
            "voltage",
        ])
        copyFirstPresent(in: ratings, to: &result, target: "current_a", keys: [
            "current_collector_ic_max",
            "current_collector_max",
            "collector_current",
            "current_rating",
            "current",
        ])
        copyFirstPresent(in: ratings, to: &result, target: "power_w", keys: [
            "power_max",
            "power_dissipation",
            "power_rating",
            "power",
        ])
        return result
    }

    private func offerObjects(from part: [String: Any]) -> [[String: Any]] {
        objects(forAnyKey: ["Offers", "offers", "DistributorOffers", "distributorOffers", "Sellers", "sellers"], in: part)
    }

    private func objects(forAnyKey keys: [String], in object: [String: Any]) -> [[String: Any]] {
        for key in keys {
            guard let value = object[key] else { continue }
            if let rows = value as? [[String: Any]] { return rows }
            if let row = value as? [String: Any] { return [row] }
        }
        return []
    }

    private func string(_ object: [String: Any], keys: [String], nestedKeys: [String] = []) -> String {
        for key in keys {
            guard let value = object[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            if let nested = value as? [String: Any] {
                let nested = string(nested, keys: nestedKeys.isEmpty ? keys : nestedKeys)
                if !nested.isEmpty { return nested }
            }
        }
        return ""
    }

    private func int(_ object: [String: Any], keys: [String]) -> Int {
        for key in keys {
            guard let value = object[key] else { continue }
            if let int = value as? Int { return int }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String {
                let digits = string.filter { $0.isNumber }
                if let int = Int(digits) { return int }
            }
        }
        return 0
    }

    private func copyFirstPresent(from object: [String: Any], to result: inout [String: String], target: String, keys: [String]) {
        guard result[target]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else { return }
        let value = string(object, keys: keys)
        if !value.isEmpty {
            result[target] = value
        }
    }

    private func copyFirstPresent(in source: [String: String], to result: inout [String: String], target: String, keys: [String]) {
        let value = firstPresent(in: source, keys: keys)
        if !value.isEmpty {
            let current = result[target]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if current.isEmpty || (!containsUnitLikeText(current) && containsUnitLikeText(value)) {
                result[target] = value
            }
        }
    }

    private func containsUnitLikeText(_ value: String) -> Bool {
        value.contains { $0.isLetter || $0 == "%" || $0 == "Ω" || $0 == "µ" }
    }

    private func firstPresent(in values: [String: String], keys: [String]) -> String {
        for key in keys {
            if let value = values[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return ""
    }
}

struct LiveMouserCatalogProvider: LiveCatalogProviderClient {
    let providerID = "mouser"
    var apiKey: String
    var endpoint: URL
    var resultLimit: Int
    var transport: any CatalogHTTPTransport
    var now: @Sendable () -> Date

    init(
        apiKey: String,
        endpoint: URL = URL(string: "https://api.mouser.com/api/v2/search/keyword")!,
        resultLimit: Int = 10,
        transport: any CatalogHTTPTransport = URLSession.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.resultLimit = resultLimit
        self.transport = transport
        self.now = now
    }

    func search(_ request: ComponentSearchRequest) async throws -> [ComponentCandidate] {
        try await searchWithRawResponse(request).candidates
    }

    func searchWithRawResponse(_ request: ComponentSearchRequest) async throws -> LiveCatalogSearchResult {
        let keyword = CatalogSearchQueryBuilder().keyword(for: request)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "apiKey", value: apiKey))
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw LiveCatalogProviderError.invalidEndpoint(endpoint.absoluteString)
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: 20)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "SearchByKeywordRequest": [
                "keyword": keyword,
                "records": resultLimit,
                "startingRecord": 0,
                "searchOptions": "InStock",
                "searchWithYourSignUpLanguage": "en",
            ],
        ])

        let (data, response) = try await transport.data(for: urlRequest)
        try validate(response: response)
        let retrievedAt = ISO8601DateFormatter().string(from: now())
        let candidates = try MouserCatalogProviderAdapter()
            .mapRecordedResponse(data)
            .map { liveAnnotated($0, retrievedAt: retrievedAt, cachePolicy: "live_api") }
        return LiveCatalogSearchResult(candidates: candidates, rawResponse: data, requestURL: url)
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 {
            throw LiveCatalogProviderError.rateLimited(retryAfterSeconds: retryAfterSeconds(from: http))
        }
        guard (200...299).contains(http.statusCode) else {
            throw LiveCatalogProviderError.httpStatus(http.statusCode)
        }
    }
}

struct LiveDigiKeyCatalogProvider: LiveCatalogProviderClient {
    let providerID = "digikey"
    var clientID: String
    var clientSecret: String?
    var accessToken: String?
    var searchEndpoint: URL
    var tokenEndpoint: URL
    var resultLimit: Int
    var transport: any CatalogHTTPTransport
    var now: @Sendable () -> Date

    init(
        clientID: String,
        clientSecret: String? = nil,
        accessToken: String? = nil,
        searchEndpoint: URL = URL(string: "https://api.digikey.com/products/v4/search/keyword")!,
        tokenEndpoint: URL = URL(string: "https://api.digikey.com/v1/oauth2/token")!,
        resultLimit: Int = 10,
        transport: any CatalogHTTPTransport = URLSession.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.accessToken = accessToken
        self.searchEndpoint = searchEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.resultLimit = resultLimit
        self.transport = transport
        self.now = now
    }

    func search(_ request: ComponentSearchRequest) async throws -> [ComponentCandidate] {
        try await searchWithRawResponse(request).candidates
    }

    func searchWithRawResponse(_ request: ComponentSearchRequest) async throws -> LiveCatalogSearchResult {
        let token = try await resolvedAccessToken()
        let keyword = CatalogSearchQueryBuilder().keyword(for: request)
        var urlRequest = URLRequest(url: searchEndpoint, timeoutInterval: 20)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(clientID, forHTTPHeaderField: "X-DIGIKEY-Client-Id")
        urlRequest.setValue("en", forHTTPHeaderField: "X-DIGIKEY-Locale-Language")
        urlRequest.setValue("US", forHTTPHeaderField: "X-DIGIKEY-Locale-Site")
        urlRequest.setValue("USD", forHTTPHeaderField: "X-DIGIKEY-Locale-Currency")
        urlRequest.setValue("US", forHTTPHeaderField: "X-DIGIKEY-Locale-ShipTo")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "Keywords": keyword,
            "Limit": resultLimit,
            "Offset": 0,
        ])

        let (data, response) = try await transport.data(for: urlRequest)
        try validate(response: response)
        let retrievedAt = ISO8601DateFormatter().string(from: now())
        let candidates = try DigiKeyCatalogProviderAdapter()
            .mapRecordedResponse(data)
            .map { liveAnnotated($0, retrievedAt: retrievedAt, cachePolicy: "live_api") }
        return LiveCatalogSearchResult(candidates: candidates, rawResponse: data, requestURL: searchEndpoint)
    }

    private func resolvedAccessToken() async throws -> String {
        if let accessToken, !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return accessToken
        }
        guard let clientSecret, !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveCatalogProviderError.missingCredential("DIGIKEY_CLIENT_SECRET")
        }
        var request = URLRequest(url: tokenEndpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "client_credentials",
        ]
            .map { "\($0.key)=\(urlFormEscaped($0.value))" }
            .joined(separator: "&")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await transport.data(for: request)
        try validate(response: response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveCatalogProviderError.missingAccessToken
        }
        return token
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 {
            throw LiveCatalogProviderError.rateLimited(retryAfterSeconds: retryAfterSeconds(from: http))
        }
        guard (200...299).contains(http.statusCode) else {
            throw LiveCatalogProviderError.httpStatus(http.statusCode)
        }
    }
}

private func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
    let value = response.value(forHTTPHeaderField: "Retry-After")?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, !value.isEmpty else { return nil }
    if let seconds = Int(value) {
        return seconds
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
    if let date = formatter.date(from: value) {
        return max(0, Int(date.timeIntervalSinceNow.rounded(.up)))
    }
    return nil
}

struct LiveNexarCatalogProvider: LiveCatalogProviderClient {
    let providerID = "nexar"
    var clientID: String
    var clientSecret: String?
    var accessToken: String?
    var graphqlEndpoint: URL
    var tokenEndpoint: URL
    var resultLimit: Int
    var transport: any CatalogHTTPTransport
    var now: @Sendable () -> Date

    init(
        clientID: String,
        clientSecret: String? = nil,
        accessToken: String? = nil,
        graphqlEndpoint: URL = URL(string: "https://api.nexar.com/graphql/")!,
        tokenEndpoint: URL = URL(string: "https://identity.nexar.com/connect/token")!,
        resultLimit: Int = 10,
        transport: any CatalogHTTPTransport = URLSession.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.accessToken = accessToken
        self.graphqlEndpoint = graphqlEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.resultLimit = resultLimit
        self.transport = transport
        self.now = now
    }

    func search(_ request: ComponentSearchRequest) async throws -> [ComponentCandidate] {
        try await searchWithRawResponse(request).candidates
    }

    func searchWithRawResponse(_ request: ComponentSearchRequest) async throws -> LiveCatalogSearchResult {
        let token = try await resolvedAccessToken()
        let keyword = CatalogSearchQueryBuilder().keyword(for: request)
        let mpnSearch = isMPNSearch(request)
        var urlRequest = URLRequest(url: graphqlEndpoint, timeoutInterval: 20)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": graphQLQuery(mpnSearch: mpnSearch),
            "variables": [
                "q": keyword,
                "limit": max(1, min(resultLimit, 100)),
            ],
        ])

        let (data, response) = try await transport.data(for: urlRequest)
        try validate(response: response)
        let retrievedAt = ISO8601DateFormatter().string(from: now())
        let candidates = try NexarCatalogProviderAdapter()
            .mapRecordedResponse(data)
            .map { liveAnnotated($0, retrievedAt: retrievedAt, cachePolicy: "live_api") }
        return LiveCatalogSearchResult(candidates: candidates, rawResponse: data, requestURL: graphqlEndpoint)
    }

    private func resolvedAccessToken() async throws -> String {
        if let accessToken, !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return accessToken
        }
        guard let clientSecret, !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveCatalogProviderError.missingCredential("NEXAR_CLIENT_SECRET")
        }
        var request = URLRequest(url: tokenEndpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "client_credentials",
            "scope": "supply.domain",
        ]
            .map { "\($0.key)=\(urlFormEscaped($0.value))" }
            .joined(separator: "&")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await transport.data(for: request)
        try validate(response: response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveCatalogProviderError.missingAccessToken
        }
        return token
    }

    private func isMPNSearch(_ request: ComponentSearchRequest) -> Bool {
        ["manufacturer_part_number", "mpn"].contains { key in
            !(request.constraints[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func graphQLQuery(mpnSearch: Bool) -> String {
        let operation = mpnSearch ? "supSearchMpn" : "supSearch"
        return """
        query MerlinComponentSearch($q: String!, $limit: Int!) {
          \(operation)(q: $q, limit: $limit, country: "US") {
            hits
            results {
              description
              part {
                id
                name
                mpn
                shortDescription
                totalAvail
                manufacturer { name homepageUrl }
                category { name }
                specs { attribute { name shortname } displayValue value unitsSymbol unitsName }
                bestDatasheet { url }
                sellers(authorizedOnly: true) {
                  company { name }
                  offers { inventoryLevel }
                }
              }
            }
          }
        }
        """
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 {
            throw LiveCatalogProviderError.rateLimited(retryAfterSeconds: retryAfterSeconds(from: http))
        }
        guard (200...299).contains(http.statusCode) else {
            throw LiveCatalogProviderError.httpStatus(http.statusCode)
        }
    }
}

struct LiveTrustedPartsCatalogProvider: LiveCatalogProviderClient {
    let providerID = "trustedparts"
    var companyID: String
    var apiKey: String
    var endpoint: URL
    var resultLimit: Int
    var transport: any CatalogHTTPTransport
    var now: @Sendable () -> Date

    init(
        companyID: String,
        apiKey: String,
        endpoint: URL = URL(string: "https://api.trustedparts.com/v2/search")!,
        resultLimit: Int = 10,
        transport: any CatalogHTTPTransport = URLSession.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.companyID = companyID
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.resultLimit = resultLimit
        self.transport = transport
        self.now = now
    }

    func search(_ request: ComponentSearchRequest) async throws -> [ComponentCandidate] {
        try await searchWithRawResponse(request).candidates
    }

    func searchWithRawResponse(_ request: ComponentSearchRequest) async throws -> LiveCatalogSearchResult {
        let keyword = CatalogSearchQueryBuilder().keyword(for: request)
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 20)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "CompanyId": companyID,
            "ApiKey": apiKey,
            "UserAgent": "Merlin electronics plugin component selection",
            "CountryCode": "US",
            "CurrencyCode": "USD",
            "Queries": [
                [
                    "SearchToken": keyword,
                    "ExactMatch": isMPNSearch(request),
                    "InStockOnly": true,
                    "MaxResults": max(1, min(resultLimit, 100)),
                ],
            ],
        ])

        let (data, response) = try await transport.data(for: urlRequest)
        try validate(response: response)
        let retrievedAt = ISO8601DateFormatter().string(from: now())
        let candidates = try TrustedPartsCatalogProviderAdapter()
            .mapRecordedResponse(data)
            .map { liveAnnotated($0, retrievedAt: retrievedAt, cachePolicy: "live_api") }
        return LiveCatalogSearchResult(candidates: candidates, rawResponse: data, requestURL: endpoint)
    }

    private func isMPNSearch(_ request: ComponentSearchRequest) -> Bool {
        ["manufacturer_part_number", "mpn"].contains { key in
            !(request.constraints[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 {
            throw LiveCatalogProviderError.rateLimited(retryAfterSeconds: retryAfterSeconds(from: http))
        }
        guard (200...299).contains(http.statusCode) else {
            throw LiveCatalogProviderError.httpStatus(http.statusCode)
        }
    }
}

private func liveAnnotated(_ candidate: ComponentCandidate, retrievedAt: String, cachePolicy: String) -> ComponentCandidate {
    var candidate = candidate
    candidate.evidence = candidate.evidence.map { evidence in
        var evidence = evidence
        evidence.retrievedAt = retrievedAt
        evidence.cachePolicy = cachePolicy
        return evidence
    }
    candidate.datasheets = candidate.datasheets.map { datasheet in
        var datasheet = datasheet
        datasheet.retrievedAt = retrievedAt
        datasheet.license = cachePolicy
        return datasheet
    }
    return candidate
}

private func urlFormEscaped(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func uniqueValues(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in values {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
        seen.insert(normalized)
        ordered.append(normalized)
    }
    return ordered
}

struct CatalogProviderCredentialPolicy: Sendable, Equatable {
    var providerID: String
    var requiredCredentialKeys: [String]
    var environment: [String: String]

    var missingCredentialKeys: [String] {
        requiredCredentialKeys.filter { key in
            environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
    }

    var liveProviderEnabled: Bool {
        missingCredentialKeys.isEmpty
    }
}

struct RealCatalogLiveTestPolicy: Sendable, Equatable {
    var environment: [String: String]

    var shouldRunLiveTests: Bool {
        environment["MERLIN_LIVE_CATALOG_TESTS"] == "1"
    }
}

private enum CatalogFixtureJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected JSON object."))
        }
        return object
    }

    static func string(_ object: [String: Any]?, _ key: String, defaultValue: String = "") -> String {
        guard let value = object?[key] else { return defaultValue }
        if let string = value as? String { return string }
        return "\(value)"
    }

    static func optionalString(_ object: [String: Any], _ key: String) -> String? {
        let value = string(object, key)
        return value.isEmpty ? nil : value
    }

    static func int(_ object: [String: Any], _ key: String) -> Int {
        if let value = object[key] as? Int { return value }
        if let value = object[key] as? String { return Int(value) ?? 0 }
        if let value = object[key] as? NSNumber { return value.intValue }
        return 0
    }

    static func parameterMap(_ rows: [[String: Any]]?, nameKey: String, valueKey: String) -> [String: String] {
        (rows ?? []).reduce(into: [:]) { result, row in
            let name = string(row, nameKey)
            let value = string(row, valueKey)
            if !name.isEmpty, !value.isEmpty {
                result[name] = value
            }
        }
    }

    static func firstNonEmpty(_ values: [String]) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }

    static func categoryName(_ category: [String: Any]?) -> String {
        guard let category else { return "" }
        let childNames = (category["ChildCategories"] as? [[String: Any]] ?? [])
            .map(categoryName)
            .filter { !$0.isEmpty }
        if let deepest = childNames.first {
            return deepest
        }
        return string(category, "Name")
    }

    static func packageEvidence(_ parameters: [String: String], category: String, description: String) -> String {
        let directKeys = [
            "Package / Case",
            "Supplier Device Package",
            "Package",
            "Case",
            "Mounting Type",
            "Termination",
            "Connector Type",
            "Connector Style",
            "Size / Dimension",
        ]
        let direct = firstNonEmpty(directKeys.compactMap { parameters[$0] })
        if !direct.isEmpty {
            return direct
        }

        let combined = "\(category) \(description)".lowercased()
        if let package = firstRegexMatch(
            in: combined,
            patterns: [
                #"\btssop[- ]?\d+\b"#,
                #"\bssop[- ]?\d+\b"#,
                #"\bsoic[- ]?\d+\b"#,
                #"\bdip[- ]?\d+\b"#,
                #"\bqfn[- ]?\d+\b"#,
                #"\bsot[- ]?23\b"#,
                #"\bto[- ]?3\b"#,
                #"\bto[- ]?92\b"#,
                #"\bto[- ]?126\b"#,
                #"\bto[- ]?252\b"#,
                #"\bto[- ]?220\b"#,
                #"\bto[- ]?247\b"#,
                #"\bgbu\b"#,
                #"\bkbpc\b"#,
                #"\bdbs\b"#,
                #"\b0603\b"#,
                #"\b0805\b"#,
                #"\b1206\b"#,
            ]
        ) {
            return package.uppercased().replacingOccurrences(of: " ", with: "-")
        }
        let inferred: [(String, String)] = [
            ("smd", "SMD"),
            ("smt", "SMT"),
            ("surface mount", "surface_mount"),
            ("through hole", "through_hole"),
            ("through-hole", "through_hole"),
            ("tht", "through_hole"),
            ("radial", "Radial"),
            ("axial", "Axial"),
            ("screw terminal", "screw_terminal"),
            ("snap in", "snap_in"),
            ("snap-in", "snap_in"),
            ("lead spacing", "Radial"),
            ("ls ", "Radial"),
            ("chassis mount", "chassis_mount"),
            ("panel mount", "panel_mount"),
            ("to-3", "TO-3"),
            ("to-220", "TO-220"),
            ("to-247", "TO-247"),
            ("to-92", "TO-92"),
            ("to-126", "TO-126"),
            ("to-252", "TO-252"),
        ]
        return inferred.first { combined.contains($0.0) }?.1 ?? ""
    }

    static func normalizedWithDescription(_ values: [String: String], description: String) -> [String: String] {
        normalized(values).merging(descriptionRatings(description)) { current, _ in current }
    }

    static func normalized(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { result, entry in
            result[normalizedKey(entry.key)] = entry.value
        }
    }

    static func normalizedKey(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(scalars)
            .split(separator: "_")
            .joined(separator: "_")
    }

    private static func descriptionRatings(_ description: String) -> [String: String] {
        [
            "voltage_v": firstCapture(in: description, pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*(?:volt|volts|v)\b"#),
            "current_a": firstCapture(in: description, pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*(?:amp|amps|a)\b"#),
            "power_w": firstCapture(in: description, pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*(?:watt|watts|w)\b"#),
            "capacitance": firstValueWithUnit(in: description, pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*(uF|µF|nF|pF)\b"#),
            "resistance": firstResistanceValue(in: description),
            "positions": firstCapture(in: description, pattern: #"(?i)\b(\d+)\s*(?:pin|pins|position|positions|pos|ckt|circuit|circuits|cond|contacts?)\b"#),
            "polarity": firstCapture(in: description, pattern: #"(?i)\b(NPN|PNP|N-Channel|P-Channel)\b"#),
            "taper": firstCapture(in: description, pattern: #"(?i)\b(linear|audio|logarithmic|log)\s+taper\b"#),
        ]
            .compactMapValues { $0 }
    }

    private static func firstResistanceValue(in text: String) -> String? {
        if let value = firstValueWithUnit(in: text, pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*([kKmM]?)\s*(?:ohm|ohms|Ω)\b"#) {
            return value
        }
        return firstValueWithUnit(in: text, pattern: #"(?i)\b(\d+(?:\.\d+)?)([RrKkMm])(\d*)\b"#)
    }

    private static func firstValueWithUnit(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 2,
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        var number = String(text[numberRange])
        let unit = String(text[unitRange])
        if match.numberOfRanges > 3,
           let suffixRange = Range(match.range(at: 3), in: text),
           !text[suffixRange].isEmpty {
            number += ".\(text[suffixRange])"
        }
        return "\(number)\(unit)"
    }

    private static func firstRegexMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let match = firstMatch(in: text, pattern: pattern) {
                return match
            }
        }
        return nil
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }
}
