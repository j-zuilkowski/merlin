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
    var decisions: [PartSelectionDecision]
    var warnings: [String]
    var providers: [String]
    var cacheMetadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case decisions
        case warnings
        case providers
        case cacheMetadata = "cache_metadata"
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
        if candidate.datasheets.isEmpty {
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
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            return "Invalid catalog provider endpoint: \(endpoint)"
        case .missingCredential(let name):
            return "Missing catalog provider credential: \(name)"
        case .httpStatus(let status):
            return "Catalog provider returned HTTP \(status)."
        case .missingAccessToken:
            return "Digi-Key token response did not include an access token."
        }
    }
}

struct CatalogSearchQueryBuilder: Sendable {
    func keyword(for request: ComponentSearchRequest) -> String {
        let constraints = request.constraints
        for key in ["manufacturer_part_number", "mpn", "value", "selected_symbol"] {
            if let value = constraints[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return [request.role, request.refdes]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct LiveCatalogQueryCacheEntry: Codable, Sendable, Equatable {
    var generatedAt: Date
    var providerID: String
    var query: String
    var candidates: [ComponentCandidate]

    enum CodingKeys: String, CodingKey {
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

    init(symbols: [KiCadSymbolDefinition], footprints: [KiCadFootprintDefinition]) {
        self.symbolsByName = Dictionary(symbols.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.footprintsByName = Dictionary(footprints.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func search(_ request: ComponentSearchRequest) async throws -> [ComponentCandidate] {
        guard let symbolName = request.constraints["symbol"],
              let symbol = symbolsByName[symbolName] else {
            return []
        }
        let footprintName = request.constraints["footprint"]
        let footprint = footprintName.flatMap { footprintsByName[$0] }
        let evidence = [
            ComponentEvidence(
                providerID: providerID,
                sourceURL: nil,
                localPath: symbol.name,
                retrievedAt: "local",
                cachePolicy: "local_library",
                sha256: nil,
                extractedParameters: [
                    "symbol": symbol.name,
                    "pin_count": "\(symbol.pins.count)",
                ],
                confidence: 1.0,
                warnings: []
            ),
            footprint.map {
                ComponentEvidence(
                    providerID: providerID,
                    sourceURL: nil,
                    localPath: $0.name,
                    retrievedAt: "local",
                    cachePolicy: "local_library",
                    sha256: nil,
                    extractedParameters: [
                        "footprint": $0.name,
                        "pad_count": "\($0.pads.count)",
                    ],
                    confidence: 1.0,
                    warnings: []
                )
            },
        ].compactMap { $0 }
        let footprintCandidates = footprint.map { footprint -> [FootprintCandidate] in
            [
                FootprintCandidate(
                    library: libraryName(from: footprint.name),
                    name: footprintNameOnly(from: footprint.name),
                    packageCompatibilityEvidence: "local KiCad footprint requested by constraint",
                    pinPadMap: Dictionary(uniqueKeysWithValues: footprint.pads.compactMap { pad in
                        guard let name = pad.name, !name.isEmpty else { return nil }
                        return (name, pad.number)
                    }),
                    sourceProviderID: providerID,
                    sourcePath: footprint.name,
                    threeDModel: nil
                ),
            ]
        } ?? []

        return [
            ComponentCandidate(
                mpn: request.constraints["mpn"] ?? "kicad-local-\(symbol.name)",
                manufacturer: request.constraints["manufacturer"] ?? "local_kicad_library",
                normalizedCategory: "kicad_library_asset",
                value: request.constraints["value"],
                package: footprintName ?? request.constraints["package"] ?? "symbol_only",
                ratings: ["symbol_pin_count": "\(symbol.pins.count)"],
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
            let package = parameters["Package / Case"] ?? parameters["Package"] ?? ""
            let ratings = CatalogFixtureJSON.normalized(parameters)
            return ComponentCandidate(
                mpn: mpn,
                manufacturer: manufacturer,
                normalizedCategory: CatalogFixtureJSON.normalizedKey(CatalogFixtureJSON.string(product, "ProductDescription")),
                value: nil,
                package: package,
                ratings: ratings,
                lifecycleState: CatalogFixtureJSON.string(product, "LifecycleStatus", defaultValue: "unknown"),
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
            let package = attributes["Package / Case"] ?? attributes["Package"] ?? ""
            let ratings = CatalogFixtureJSON.normalized(attributes)
            return ComponentCandidate(
                mpn: mpn,
                manufacturer: manufacturer,
                normalizedCategory: CatalogFixtureJSON.normalizedKey(CatalogFixtureJSON.string(part, "Category")),
                value: nil,
                package: package,
                ratings: ratings,
                lifecycleState: CatalogFixtureJSON.string(part, "LifecycleStatus", defaultValue: "unknown"),
                availabilitySummary: CatalogFixtureJSON.string(part, "Availability", defaultValue: "unknown"),
                datasheets: [
                    DatasheetEvidence(
                        manufacturer: manufacturer,
                        mpn: mpn,
                        url: CatalogFixtureJSON.string(part, "DataSheetUrl"),
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
                value: nil,
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
}
