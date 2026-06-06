import Foundation

struct SPICESimulationScenario: Codable, Sendable, Equatable {
    var scenarioId: String
    var designId: String
    var circuitPath: String
    var analyses: [String]
    var requiredModelRefs: [String]
    var measurementEnvelopes: [SPICEMeasurementEnvelope]
}

struct SPICEScenarioValidation: Codable, Sendable, Equatable {
    var isValid: Bool
    var issues: [ElectronicsSchemaIssue]
}

struct SPICEScenarioValidator: Sendable {
    func validate(_ scenario: SPICESimulationScenario) -> SPICEScenarioValidation {
        var issues: [ElectronicsSchemaIssue] = []

        if scenario.circuitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ElectronicsSchemaIssue(
                code: "SPICE_CIRCUIT_PATH_REQUIRED",
                message: "\(scenario.scenarioId) requires a circuit netlist path."
            ))
        }
        if scenario.analyses.isEmpty {
            issues.append(ElectronicsSchemaIssue(
                code: "SPICE_ANALYSIS_REQUIRED",
                message: "\(scenario.scenarioId) requires at least one SPICE analysis."
            ))
        }
        if scenario.requiredModelRefs.isEmpty {
            issues.append(ElectronicsSchemaIssue(
                code: "SPICE_MODEL_REF_REQUIRED",
                message: "\(scenario.scenarioId) requires explicit SPICE model references."
            ))
        }
        if scenario.measurementEnvelopes.isEmpty {
            issues.append(ElectronicsSchemaIssue(
                code: "SPICE_MEASUREMENT_ENVELOPE_REQUIRED",
                message: "\(scenario.scenarioId) requires pass/fail measurement envelopes."
            ))
        }

        return SPICEScenarioValidation(isValid: issues.isEmpty, issues: issues)
    }
}

struct SPICEModelRecord: Codable, Sendable, Equatable {
    var modelRef: String
    var legallyUsable: Bool
    var isGeneric: Bool
}

struct SPICEModelResolution: Codable, Sendable, Equatable {
    var canSimulate: Bool
    var selectedModels: [SPICEModelRecord]
    var issues: [ElectronicsSchemaIssue]
}

struct SPICEModelResolver: Sendable {
    func resolve(
        requiredModels: [String],
        availableModels: [SPICEModelRecord],
        approvals: [ElectronicsApprovalKind]
    ) -> SPICEModelResolution {
        var selected: [SPICEModelRecord] = []
        var issues: [ElectronicsSchemaIssue] = []

        for required in requiredModels {
            if let exact = availableModels.first(where: { $0.modelRef == required && $0.legallyUsable }) {
                selected.append(exact)
                continue
            }

            if let generic = availableModels.first(where: { $0.isGeneric && $0.legallyUsable }) {
                if approvals.contains(.substitution) {
                    selected.append(generic)
                } else {
                    issues.append(ElectronicsSchemaIssue(
                        code: "SPICE_MODEL_GENERIC_APPROVAL_REQUIRED",
                        message: "\(required) is unavailable; generic substitute \(generic.modelRef) requires approval."
                    ))
                }
                continue
            }

            issues.append(ElectronicsSchemaIssue(
                code: "SPICE_MODEL_REQUIRED",
                message: "\(required) has no legal model or approved substitute."
            ))
        }

        return SPICEModelResolution(
            canSimulate: issues.isEmpty,
            selectedModels: selected,
            issues: issues
        )
    }
}

struct SPICEMeasurementReport: Codable, Sendable, Equatable {
    var measurements: [String: Double]
}

struct NgspiceMeasurementParser: Sendable {
    func parse(_ output: String) throws -> SPICEMeasurementReport {
        var measurements: [String: Double] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }
            let scalar = parts[1]
                .split(whereSeparator: \.isWhitespace)
                .first
                .map(String.init) ?? parts[1]
            guard let value = Double(scalar) else { continue }
            measurements[parts[0]] = value
        }
        return SPICEMeasurementReport(measurements: measurements)
    }
}

struct SPICEMeasurementEnvelope: Codable, Sendable, Equatable {
    var name: String
    var min: Double?
    var max: Double?
}

struct SPICEMeasurementFailure: Codable, Sendable, Equatable {
    var measurement: String
    var actual: Double
    var expected: String
}

struct SPICEMeasurementEnvelopeResult: Codable, Sendable, Equatable {
    var passed: Bool
    var failures: [SPICEMeasurementFailure]
}

struct SPICEMeasurementEnvelopeEvaluator: Sendable {
    func evaluate(
        report: SPICEMeasurementReport,
        envelopes: [SPICEMeasurementEnvelope]
    ) -> SPICEMeasurementEnvelopeResult {
        var failures: [SPICEMeasurementFailure] = []

        for envelope in envelopes {
            guard let actual = report.measurements[envelope.name] else {
                failures.append(SPICEMeasurementFailure(
                    measurement: envelope.name,
                    actual: .nan,
                    expected: expectedDescription(envelope)
                ))
                continue
            }
            if let min = envelope.min, actual < min {
                failures.append(SPICEMeasurementFailure(
                    measurement: envelope.name,
                    actual: actual,
                    expected: expectedDescription(envelope)
                ))
            } else if let max = envelope.max, actual > max {
                failures.append(SPICEMeasurementFailure(
                    measurement: envelope.name,
                    actual: actual,
                    expected: expectedDescription(envelope)
                ))
            }
        }

        return SPICEMeasurementEnvelopeResult(passed: failures.isEmpty, failures: failures)
    }

    private func expectedDescription(_ envelope: SPICEMeasurementEnvelope) -> String {
        switch (envelope.min, envelope.max) {
        case (.some(let min), .some(let max)):
            return "\(min)...\(max)"
        case (.some(let min), .none):
            return ">=\(min)"
        case (.none, .some(let max)):
            return "<=\(max)"
        case (.none, .none):
            return "measured"
        }
    }
}

enum SPICETopology: String, Codable, Sendable, Equatable {
    case singleEndedClassA = "single_ended_class_a"
}

enum SPICESimulationRepairClass: String, Codable, Sendable, Equatable {
    case parameterAdjustment = "parameter_adjustment"
    case unsupported = "unsupported"
}

struct SPICESimulationRepairPatch: Codable, Sendable, Equatable {
    var repairClass: SPICESimulationRepairClass
    var parameterName: String?
    var action: String
}

struct SPICESimulationRepairPlan: Codable, Sendable, Equatable {
    var patches: [SPICESimulationRepairPatch]
    var requiresTopologyChange: Bool
    var issues: [ElectronicsSchemaIssue]
}

struct SPICESimulationRepairPlanner: Sendable {
    func plan(
        failures: [SPICEMeasurementFailure],
        topology: SPICETopology
    ) -> SPICESimulationRepairPlan {
        var patches: [SPICESimulationRepairPatch] = []
        var issues: [ElectronicsSchemaIssue] = []

        for failure in failures {
            switch (topology, failure.measurement) {
            case (.singleEndedClassA, "output_power_w"):
                patches.append(SPICESimulationRepairPatch(
                    repairClass: .parameterAdjustment,
                    parameterName: "bias_current",
                    action: "adjust_bias_current_within_declared_bounds"
                ))
            case (.singleEndedClassA, "thd_percent"):
                patches.append(SPICESimulationRepairPatch(
                    repairClass: .parameterAdjustment,
                    parameterName: "driver_bias",
                    action: "adjust_driver_bias_within_declared_bounds"
                ))
            default:
                issues.append(ElectronicsSchemaIssue(
                    code: "SPICE_REPAIR_UNSUPPORTED",
                    message: "No supported fixed-topology repair for \(failure.measurement)."
                ))
            }
        }

        return SPICESimulationRepairPlan(
            patches: patches,
            requiresTopologyChange: false,
            issues: issues
        )
    }
}

struct SPICEParameter: Codable, Sendable, Equatable {
    var name: String
    var value: Double
    var min: Double
    var max: Double
}

struct SPICEOptimizationProposal: Codable, Sendable, Equatable {
    var parameterName: String
    var value: Double
    var changesTopology: Bool
}

struct FixedTopologySPICEOptimizationResult: Codable, Sendable, Equatable {
    var finalParameters: [String: Double]
    var applied: [SPICEOptimizationProposal]
    var rejected: [ElectronicsSchemaIssue]
}

struct FixedTopologySPICEOptimizer: Sendable {
    var maxIterations: Int

    init(maxIterations: Int = 3) {
        self.maxIterations = maxIterations
    }

    func optimize(
        topology: SPICETopology,
        parameters: [SPICEParameter],
        proposals: [SPICEOptimizationProposal]
    ) -> FixedTopologySPICEOptimizationResult {
        _ = topology
        var final = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.value) })
        let bounds = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0) })
        var applied: [SPICEOptimizationProposal] = []
        var rejected: [ElectronicsSchemaIssue] = []

        for proposal in proposals {
            if proposal.changesTopology {
                rejected.append(ElectronicsSchemaIssue(
                    code: "SPICE_TOPOLOGY_CHANGE_UNSUPPORTED",
                    message: "\(proposal.parameterName) would change topology."
                ))
                continue
            }
            guard applied.count < maxIterations else {
                rejected.append(ElectronicsSchemaIssue(
                    code: "SPICE_OPTIMIZATION_ITERATION_LIMIT",
                    message: "SPICE optimization reached \(maxIterations) iterations."
                ))
                break
            }
            guard let bound = bounds[proposal.parameterName] else {
                rejected.append(ElectronicsSchemaIssue(
                    code: "SPICE_PARAMETER_UNDECLARED",
                    message: "\(proposal.parameterName) is not a declared optimization parameter."
                ))
                continue
            }
            guard proposal.value >= bound.min && proposal.value <= bound.max else {
                rejected.append(ElectronicsSchemaIssue(
                    code: "SPICE_PARAMETER_OUT_OF_BOUNDS",
                    message: "\(proposal.parameterName) is outside declared bounds."
                ))
                continue
            }
            final[proposal.parameterName] = proposal.value
            applied.append(proposal)
        }

        if applied.count == maxIterations && proposals.count > maxIterations {
            rejected.append(ElectronicsSchemaIssue(
                code: "SPICE_OPTIMIZATION_ITERATION_LIMIT",
                message: "SPICE optimization reached \(maxIterations) iterations."
            ))
        }

        return FixedTopologySPICEOptimizationResult(
            finalParameters: final,
            applied: applied,
            rejected: rejected
        )
    }
}
