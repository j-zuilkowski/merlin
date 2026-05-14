import XCTest
@testable import Merlin

final class SchematicExtractionPolicyTests: XCTestCase {

    func test_weightedConfidence_usesSpecifiedWeights() {
        let scores = ExtractionEvidenceScores(
            geometry: 0.90,
            ocr: 0.80,
            library: 0.70,
            graph: 0.60,
            crossPass: 0.50,
            field: 0.95,
            symbol: 0.96,
            pin: 0.97,
            net: 0.98,
            contradictions: [],
            ambiguousNets: 0,
            unknownComponents: 0
        )

        let weighted = ExtractionConfidenceCalculator.weightedConfidence(scores)
        let expected = 0.90 * 0.30 + 0.80 * 0.20 + 0.70 * 0.25 + 0.60 * 0.15 + 0.50 * 0.10
        XCTAssertEqual(weighted, expected, accuracy: 0.000001)
    }

    func test_criticalFieldConfidence_isMinimumAcrossFieldSymbolPinNet() {
        let scores = ExtractionEvidenceScores(
            geometry: 0.99,
            ocr: 0.99,
            library: 0.99,
            graph: 0.99,
            crossPass: 0.99,
            field: 0.92,
            symbol: 0.88,
            pin: 0.91,
            net: 0.95,
            contradictions: [],
            ambiguousNets: 0,
            unknownComponents: 0
        )

        XCTAssertEqual(ExtractionConfidenceCalculator.criticalFieldConfidence(scores), 0.88, accuracy: 0.000001)
    }

    func test_contradiction_forcesAmbiguityRegardlessOfWeightedScore() {
        let scores = ExtractionEvidenceScores(
            geometry: 1.0,
            ocr: 1.0,
            library: 1.0,
            graph: 1.0,
            crossPass: 1.0,
            field: 1.0,
            symbol: 1.0,
            pin: 1.0,
            net: 1.0,
            contradictions: [ExtractionContradiction(code: "PIN_MISMATCH", message: "Symbol pin count mismatch")],
            ambiguousNets: 0,
            unknownComponents: 0
        )

        XCTAssertTrue(ExtractionConfidenceCalculator.isAmbiguous(scores))
    }

    func test_lowDPI_blocksInputQuality() {
        let policy = SchematicExtractionPolicy.default
        let decision = policy.evaluate(
            sourceType: .rasterImage,
            dpi: 180,
            evidence: .baseline,
            sourceRegions: []
        )

        XCTAssertEqual(decision.status, .blockedInputQuality)
        XCTAssertFalse(decision.mayProceedToPCBSynthesis)
    }

    func test_handDrawnInput_isConceptualUnlessThresholdsMet() {
        let policy = SchematicExtractionPolicy.default

        let weak = policy.evaluate(
            sourceType: .handDrawn,
            dpi: 300,
            evidence: .init(
                geometry: 0.80,
                ocr: 0.75,
                library: 0.84,
                graph: 0.77,
                crossPass: 0.79,
                field: 0.80,
                symbol: 0.81,
                pin: 0.70,
                net: 0.68,
                contradictions: [],
                ambiguousNets: 0,
                unknownComponents: 0
            ),
            sourceRegions: []
        )
        XCTAssertEqual(weak.status, .blockedInputQuality)
        XCTAssertFalse(weak.mayProceedToPCBSynthesis)

        let strong = policy.evaluate(
            sourceType: .handDrawn,
            dpi: 300,
            evidence: .init(
                geometry: 0.995,
                ocr: 0.992,
                library: 0.996,
                graph: 0.993,
                crossPass: 0.994,
                field: 0.996,
                symbol: 0.997,
                pin: 0.995,
                net: 0.995,
                contradictions: [],
                ambiguousNets: 0,
                unknownComponents: 0
            ),
            sourceRegions: []
        )
        XCTAssertNil(strong.status)
        XCTAssertTrue(strong.mayProceedToPCBSynthesis)
    }

    func test_ambiguousNets_createClarificationQuestionsWithSourceRegions() {
        let planner = ClarificationPlanner()
        let questions = planner.plan(
            designId: "design-ambig",
            evidence: .init(
                geometry: 0.90,
                ocr: 0.90,
                library: 0.90,
                graph: 0.90,
                crossPass: 0.90,
                field: 0.90,
                symbol: 0.90,
                pin: 0.90,
                net: 0.90,
                contradictions: [],
                ambiguousNets: 2,
                unknownComponents: 0
            ),
            sourceRegions: [SourceRegion(page: 2, x: 50, y: 60, width: 30, height: 40)]
        )

        XCTAssertFalse(questions.isEmpty)
        XCTAssertTrue(questions.contains(where: { $0.prompt.contains("ambiguous") }))
        XCTAssertTrue(questions.contains(where: { $0.affectedRefs.contains("page:2") }))
    }

    func test_rasterAndPDFExtraction_doNotProceedWhenAmbiguityOrUnknownComponentsExist() {
        let policy = SchematicExtractionPolicy.default

        let ambiguous = policy.evaluate(
            sourceType: .rasterImage,
            dpi: 300,
            evidence: .init(
                geometry: 0.98,
                ocr: 0.98,
                library: 0.98,
                graph: 0.98,
                crossPass: 0.98,
                field: 0.98,
                symbol: 0.98,
                pin: 0.98,
                net: 0.98,
                contradictions: [],
                ambiguousNets: 1,
                unknownComponents: 0
            ),
            sourceRegions: []
        )
        XCTAssertFalse(ambiguous.mayProceedToPCBSynthesis)

        let unknown = policy.evaluate(
            sourceType: .vectorPDF,
            dpi: 300,
            evidence: .init(
                geometry: 0.98,
                ocr: 0.98,
                library: 0.98,
                graph: 0.98,
                crossPass: 0.98,
                field: 0.98,
                symbol: 0.98,
                pin: 0.98,
                net: 0.98,
                contradictions: [],
                ambiguousNets: 0,
                unknownComponents: 1
            ),
            sourceRegions: []
        )
        XCTAssertFalse(unknown.mayProceedToPCBSynthesis)
    }
}

private extension ExtractionEvidenceScores {
    static let baseline = ExtractionEvidenceScores(
        geometry: 0.95,
        ocr: 0.95,
        library: 0.95,
        graph: 0.95,
        crossPass: 0.95,
        field: 0.95,
        symbol: 0.95,
        pin: 0.95,
        net: 0.95,
        contradictions: [],
        ambiguousNets: 0,
        unknownComponents: 0
    )
}
