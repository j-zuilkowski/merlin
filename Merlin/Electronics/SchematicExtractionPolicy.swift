import Foundation

struct ExtractionEvidenceScores: Codable, Sendable, Equatable {
    var geometry: Double
    var ocr: Double
    var library: Double
    var graph: Double
    var crossPass: Double
    var field: Double
    var symbol: Double
    var pin: Double
    var net: Double
    var contradictions: [ExtractionContradiction]
    var ambiguousNets: Int
    var unknownComponents: Int

    enum CodingKeys: String, CodingKey {
        case geometry
        case ocr
        case library
        case graph
        case crossPass = "cross_pass"
        case field
        case symbol
        case pin
        case net
        case contradictions
        case ambiguousNets = "ambiguous_nets"
        case unknownComponents = "unknown_components"
    }
}

struct ExtractionContradiction: Codable, Sendable, Equatable {
    var code: String
    var message: String
}

enum ExtractionConfidenceCalculator {
    static func weightedConfidence(_ scores: ExtractionEvidenceScores) -> Double {
        (scores.geometry * 0.30)
        + (scores.ocr * 0.20)
        + (scores.library * 0.25)
        + (scores.graph * 0.15)
        + (scores.crossPass * 0.10)
    }

    static func criticalFieldConfidence(_ scores: ExtractionEvidenceScores) -> Double {
        min(scores.field, scores.symbol, scores.pin, scores.net)
    }

    static func isAmbiguous(_ scores: ExtractionEvidenceScores) -> Bool {
        !scores.contradictions.isEmpty || scores.ambiguousNets > 0 || scores.unknownComponents > 0
    }
}

struct SchematicExtractionPolicy: Sendable {
    static let `default` = SchematicExtractionPolicy()

    var minDPI: Int = 300
    var handDrawnWeightedThreshold: Double = 0.985
    var handDrawnCriticalThreshold: Double = 0.995

    func evaluate(sourceType: SchematicInputKind,
                  dpi: Int,
                  evidence: ExtractionEvidenceScores,
                  sourceRegions: [SourceRegion]) -> SchematicInputDecision {
        if dpi < minDPI {
            return SchematicInputDecision(
                disposition: .conceptualOnly,
                status: .blockedInputQuality,
                mayProceedToPCBSynthesis: false,
                message: "Input DPI is below minimum extraction threshold."
            )
        }

        let weighted = ExtractionConfidenceCalculator.weightedConfidence(evidence)
        let critical = ExtractionConfidenceCalculator.criticalFieldConfidence(evidence)

        if !evidence.contradictions.isEmpty {
            return SchematicInputDecision(
                disposition: .conceptualOnly,
                status: .blockedInputQuality,
                mayProceedToPCBSynthesis: false,
                message: "Extraction contradictions were detected and require clarification."
            )
        }

        if (sourceType == .rasterImage || sourceType == .vectorPDF)
            && (evidence.ambiguousNets > 0 || evidence.unknownComponents > 0) {
            return SchematicInputDecision(
                disposition: .conceptualOnly,
                status: .blockedInputQuality,
                mayProceedToPCBSynthesis: false,
                message: "Raster/PDF extraction contains ambiguities that require clarification before synthesis."
            )
        }

        if sourceType == .handDrawn {
            let handDrawnPasses = weighted >= handDrawnWeightedThreshold
                && critical >= handDrawnCriticalThreshold
                && evidence.ambiguousNets == 0
                && evidence.unknownComponents == 0

            if !handDrawnPasses {
                return SchematicInputDecision(
                    disposition: .conceptualOnly,
                    status: .blockedInputQuality,
                    mayProceedToPCBSynthesis: false,
                    message: "Hand-drawn schematics are conceptual unless authoritative extraction thresholds are met."
                )
            }
        }

        if evidence.ambiguousNets > 0 || evidence.unknownComponents > 0 {
            return SchematicInputDecision(
                disposition: .conceptualOnly,
                status: .blockedInputQuality,
                mayProceedToPCBSynthesis: false,
                message: "Extraction ambiguity requires user clarification."
            )
        }

        return SchematicInputDecision(
            disposition: .authoritative,
            status: nil,
            mayProceedToPCBSynthesis: true,
            message: "Extraction evidence meets synthesis thresholds."
        )
    }
}

struct ClarificationPlanner: Sendable {
    func plan(designId: String,
              evidence: ExtractionEvidenceScores,
              sourceRegions: [SourceRegion]) -> [ClarificationQuestion] {
        var questions: [ClarificationQuestion] = []

        let regionRefs = sourceRegions.map { "page:\($0.page)" }

        if evidence.ambiguousNets > 0 {
            questions.append(ClarificationQuestion(
                id: "\(designId)-ambiguous-nets",
                prompt: "Resolve ambiguous net connectivity before synthesis (\(evidence.ambiguousNets) unresolved).",
                affectedRefs: regionRefs
            ))
        }

        if evidence.unknownComponents > 0 {
            questions.append(ClarificationQuestion(
                id: "\(designId)-unknown-components",
                prompt: "Identify unknown components before synthesis (\(evidence.unknownComponents) unresolved).",
                affectedRefs: regionRefs
            ))
        }

        for contradiction in evidence.contradictions {
            questions.append(ClarificationQuestion(
                id: "\(designId)-contradiction-\(contradiction.code.lowercased())",
                prompt: "Resolve contradiction: \(contradiction.message)",
                affectedRefs: regionRefs
            ))
        }

        return questions
    }
}

struct SchematicExtractionResultBuilder: Sendable {
    var policy: SchematicExtractionPolicy
    var planner: ClarificationPlanner

    init(policy: SchematicExtractionPolicy = .default,
         planner: ClarificationPlanner = ClarificationPlanner()) {
        self.policy = policy
        self.planner = planner
    }

    func build(designId: String,
               sourceType: SchematicInputKind,
               dpi: Int,
               evidence: ExtractionEvidenceScores,
               sourceRegions: [SourceRegion],
               extractedComponents: [ExtractedComponent],
               extractedNets: [ExtractedNet]) -> (report: ExtractionReport, decision: SchematicInputDecision, questions: [ClarificationQuestion]) {
        let decision = policy.evaluate(
            sourceType: sourceType,
            dpi: dpi,
            evidence: evidence,
            sourceRegions: sourceRegions
        )

        let questions = planner.plan(
            designId: designId,
            evidence: evidence,
            sourceRegions: sourceRegions
        )

        let report = ExtractionReport(
            designId: designId,
            sourceType: sourceType.rawValue,
            extractedComponents: extractedComponents,
            extractedNets: extractedNets,
            confidence: ExtractionConfidence(
                overall: ExtractionConfidenceCalculator.weightedConfidence(evidence),
                criticalFields: ExtractionConfidenceCalculator.criticalFieldConfidence(evidence)
            ),
            sourceRegions: sourceRegions,
            warnings: decision.mayProceedToPCBSynthesis ? [] : [decision.message]
        )

        return (report, decision, questions)
    }
}
