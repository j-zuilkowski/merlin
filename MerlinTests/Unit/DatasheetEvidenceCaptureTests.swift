import XCTest
@testable import Merlin

final class DatasheetEvidenceCaptureTests: XCTestCase {
    func testDatasheetMetadataCapturesRequiredSourceFields() throws {
        let evidence = try DatasheetEvidenceBuilder().metadata(
            manufacturer: "onsemi",
            mpn: "MJ15003G",
            url: "https://example.invalid/MJ15003G-D.PDF",
            localPath: nil,
            providerID: "fixture",
            retrievedAt: "2026-05-30T16:00:00Z",
            license: "fixture"
        )

        XCTAssertEqual(evidence.manufacturer, "onsemi")
        XCTAssertEqual(evidence.mpn, "MJ15003G")
        XCTAssertEqual(evidence.url, "https://example.invalid/MJ15003G-D.PDF")
        XCTAssertNil(evidence.localPath)
        XCTAssertNil(evidence.sha256)
        XCTAssertEqual(evidence.providerID, "fixture")
        XCTAssertEqual(evidence.retrievedAt, "2026-05-30T16:00:00Z")
        XCTAssertEqual(evidence.license, "fixture")
        XCTAssertTrue(evidence.citations.isEmpty)
    }

    func testLocalDatasheetRecordsSHA256WhenStored() throws {
        let directory = try temporaryDirectory()
        let pdfURL = directory.appendingPathComponent("datasheet.pdf")
        let bytes = Data("fixture pdf bytes".utf8)
        try bytes.write(to: pdfURL)

        let evidence = try DatasheetEvidenceBuilder().metadata(
            manufacturer: "onsemi",
            mpn: "MJ15003G",
            url: "https://example.invalid/MJ15003G-D.PDF",
            localPath: pdfURL.path,
            providerID: "fixture",
            retrievedAt: "2026-05-30T16:00:00Z",
            license: "fixture"
        )

        XCTAssertEqual(evidence.localPath, pdfURL.path)
        XCTAssertEqual(evidence.sha256, "0c4d2d351e2954b4a7a3e1f60845b09cb5474e45acb095563f6c9d01b55fd187")
    }

    func testMissingDatasheetEvidenceBlocksReleaseGradeCandidate() {
        let candidate = ComponentCandidate(
            mpn: "MJ15003G",
            manufacturer: "onsemi",
            normalizedCategory: "bipolar_power_transistor",
            value: nil,
            package: "TO-3",
            ratings: ["power_w": "250"],
            lifecycleState: "active",
            availabilitySummary: "fixture_available",
            datasheets: [],
            evidence: [
                ComponentEvidence(
                    providerID: "fixture",
                    sourceURL: "https://example.invalid/MJ15003G",
                    localPath: nil,
                    retrievedAt: "2026-05-30T16:00:00Z",
                    cachePolicy: "fixture_no_cache",
                    sha256: nil,
                    extractedParameters: ["mpn": "MJ15003G"],
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: []
        )

        let result = ComponentCatalogValidator().validate(candidate)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "DATASHEET_REQUIRED"))
    }

    func testRAGCitationFieldsAreOptionalAndAbsentByDefault() throws {
        let evidence = try DatasheetEvidenceBuilder().metadata(
            manufacturer: "Yageo",
            mpn: "RC0603FR-0710KL",
            url: "https://example.invalid/resistor.pdf",
            localPath: nil,
            providerID: "fixture",
            retrievedAt: "2026-05-30T16:00:00Z",
            license: "fixture"
        )

        XCTAssertEqual(evidence.citations, [])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as? [String: Any]
        XCTAssertNotNil(encoded?["citations"])
        XCTAssertNil(encoded?["rag_chunks"])
        XCTAssertNil(encoded?["page_embeddings"])
    }

    func testDatasheetPDFCacheReusesLocalPDFBeforeNetwork() async throws {
        let directory = try temporaryDirectory()
        let evidence = try DatasheetEvidenceBuilder().metadata(
            manufacturer: "onsemi",
            mpn: "MJ15003G",
            url: "https://example.invalid/MJ15003G-D.PDF",
            localPath: nil,
            providerID: "mouser",
            retrievedAt: "2026-05-30T16:00:00Z",
            license: "live_api"
        )
        let firstTransport = MockDatasheetHTTPTransport(responses: [
            .init(data: Data("%PDF-1.7 first datasheet".utf8)),
        ])

        let first = try await DatasheetPDFCache().resolve(
            evidence,
            in: directory,
            revalidateAfterSeconds: 86_400,
            transport: firstTransport,
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(firstTransport.requests.count, 1)
        XCTAssertNotNil(first.localPath)
        XCTAssertNotNil(first.sha256)

        let secondTransport = MockDatasheetHTTPTransport(responses: [])
        let second = try await DatasheetPDFCache().resolve(
            evidence,
            in: directory,
            revalidateAfterSeconds: 86_400,
            transport: secondTransport,
            now: Date(timeIntervalSince1970: 1_030)
        )

        XCTAssertEqual(secondTransport.requests.count, 0)
        XCTAssertEqual(second.localPath, first.localPath)
        XCTAssertEqual(second.sha256, first.sha256)
    }

    func testDatasheetPDFCacheReplacesLocalPDFWhenRevalidatedContentChanges() async throws {
        let directory = try temporaryDirectory()
        let evidence = try DatasheetEvidenceBuilder().metadata(
            manufacturer: "onsemi",
            mpn: "MJ15003G",
            url: "https://example.invalid/MJ15003G-D.PDF",
            localPath: nil,
            providerID: "mouser",
            retrievedAt: "2026-05-30T16:00:00Z",
            license: "live_api"
        )
        let firstTransport = MockDatasheetHTTPTransport(responses: [
            .init(data: Data("%PDF-1.7 first datasheet".utf8), headers: ["ETag": "\"v1\""]),
        ])
        let first = try await DatasheetPDFCache().resolve(
            evidence,
            in: directory,
            revalidateAfterSeconds: 1,
            transport: firstTransport,
            now: Date(timeIntervalSince1970: 1_000)
        )
        let firstPath = try XCTUnwrap(first.localPath)

        let secondTransport = MockDatasheetHTTPTransport(responses: [
            .init(data: Data("%PDF-1.7 changed datasheet".utf8), headers: ["ETag": "\"v2\""]),
        ])
        let second = try await DatasheetPDFCache().resolve(
            evidence,
            in: directory,
            revalidateAfterSeconds: 1,
            transport: secondTransport,
            now: Date(timeIntervalSince1970: 1_010)
        )

        XCTAssertEqual(secondTransport.requests.count, 1)
        XCTAssertEqual(secondTransport.requests.first?.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
        XCTAssertEqual(second.localPath, firstPath)
        XCTAssertNotEqual(second.sha256, first.sha256)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: firstPath)), Data("%PDF-1.7 changed datasheet".utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-datasheet-evidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class MockDatasheetHTTPTransport: CatalogHTTPTransport, @unchecked Sendable {
    struct Response: Sendable {
        var data: Data
        var statusCode: Int
        var headers: [String: String]

        init(data: Data, statusCode: Int = 200, headers: [String: String] = [:]) {
            self.data = data
            self.statusCode = statusCode
            self.headers = headers
        }
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let next = responses.isEmpty ? Response(data: Data(), statusCode: 500) : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: next.statusCode,
            httpVersion: nil,
            headerFields: next.headers
        )!
        return (next.data, response)
    }
}
