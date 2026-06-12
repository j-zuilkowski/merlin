import XCTest
@testable import Merlin

final class KiCadLibraryPinResolverTests: XCTestCase {
    func testKnownSymbolAndFootprintResolvePinsAndPads() {
        let resolver = fixtureResolver()
        let result = resolver.resolve(component: validTransistor(), pcbBound: true)

        XCTAssertTrue(result.isResolved)
        XCTAssertEqual(result.symbolEvidence?.symbolName, "Device:Q_NPN_BCE")
        XCTAssertEqual(result.symbolEvidence?.pins.map(\.name), ["B", "C", "E"])
        XCTAssertEqual(result.footprintEvidence?.footprintName, "Package_TO_SOT_THT:TO-3P-3_Vertical")
        XCTAssertEqual(result.footprintEvidence?.pads.map(\.number), ["1", "2", "3"])
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testSymbolPinToFootprintPadCompatibilityPasses() {
        let resolver = fixtureResolver()
        let result = resolver.resolve(component: validTransistor(), pcbBound: true)

        XCTAssertEqual(result.pinPadMap, [
            "B": "1",
            "C": "2",
            "E": "3",
        ])
    }

    func testUnknownSymbolBlocks() {
        let resolver = fixtureResolver()
        var component = validTransistor()
        component.selectedSymbol = "Device:Q_UNKNOWN"

        let result = resolver.resolve(component: component, pcbBound: true)

        XCTAssertFalse(result.isResolved)
        XCTAssertTrue(result.contains(code: "UNKNOWN_SYMBOL"))
    }

    func testUnknownFootprintBlocksPCBBoundComponent() {
        let resolver = fixtureResolver()
        var component = validTransistor()
        component.selectedFootprint = "Package:Missing"

        let result = resolver.resolve(component: component, pcbBound: true)

        XCTAssertFalse(result.isResolved)
        XCTAssertTrue(result.contains(code: "UNKNOWN_FOOTPRINT"))
    }

    func testPinMismatchBlocks() {
        let resolver = fixtureResolver()
        var component = validTransistor()
        component.pins[0].symbolPin = "X"

        let result = resolver.resolve(component: component, pcbBound: true)

        XCTAssertFalse(result.isResolved)
        XCTAssertTrue(result.contains(code: "PIN_MISMATCH"))
    }

    func testMissingMPNAndUnresolvedPackageBlockPCBBoundComponent() {
        let resolver = fixtureResolver()
        var component = validTransistor()
        component.manufacturerPartNumber = nil
        component.selectedFootprint = nil

        let result = resolver.resolve(component: component, pcbBound: true)

        XCTAssertFalse(result.isResolved)
        XCTAssertTrue(result.contains(code: "MPN_MISSING"))
        XCTAssertTrue(result.contains(code: "PACKAGE_UNRESOLVED"))
    }

    private func fixtureResolver() -> KiCadLibraryPinResolver {
        KiCadLibraryPinResolver(
            symbols: [
                KiCadSymbolDefinition(
                    name: "Device:Q_NPN_BCE",
                    pins: [
                        KiCadSymbolPin(number: "1", name: "B", electricalType: "input"),
                        KiCadSymbolPin(number: "2", name: "C", electricalType: "power"),
                        KiCadSymbolPin(number: "3", name: "E", electricalType: "passive"),
                    ]
                ),
            ],
            footprints: [
                KiCadFootprintDefinition(
                    name: "Package_TO_SOT_THT:TO-3P-3_Vertical",
                    pads: [
                        KiCadFootprintPad(number: "1", name: "B"),
                        KiCadFootprintPad(number: "2", name: "C"),
                        KiCadFootprintPad(number: "3", name: "E"),
                    ]
                ),
            ]
        )
    }

    private func validTransistor() -> CircuitComponent {
        CircuitComponent(
            refdes: "Q1",
            role: "Class-A output transistor",
            selectedSymbol: "Device:Q_NPN_BCE",
            selectedFootprint: "Package_TO_SOT_THT:TO-3P-3_Vertical",
            manufacturerPartNumber: "MJ15003G",
            sourceEvidence: [
                SourceEvidence(kind: "datasheet", reference: "onsemi MJ15003G datasheet"),
            ],
            pins: [
                CircuitPin(componentRefdes: "Q1", pinNumber: "1", canonicalName: "B", electricalType: "input", symbolPin: "B", footprintPad: "1"),
                CircuitPin(componentRefdes: "Q1", pinNumber: "2", canonicalName: "C", electricalType: "power", symbolPin: "C", footprintPad: "2"),
                CircuitPin(componentRefdes: "Q1", pinNumber: "3", canonicalName: "E", electricalType: "passive", symbolPin: "E", footprintPad: "3"),
            ]
        )
    }
}
