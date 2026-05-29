import XCTest
@testable import Merlin

final class ToolDiscoveryTests: XCTestCase {

    // `summarize: false` skips the per-tool `--help` probe. The probe spawns
    // a 2 s-timeout subprocess for every executable on `$PATH`; on a CI
    // runner that means hundreds of subprocesses and roughly 5–15 minutes
    // per call, which wedged the unit suite. These tests verify the
    // discovery contract (common tools present, names deduplicated), not
    // the summary side-effect, so the probe is unnecessary.

    func testScanFindsCommonTools() async {
        let tools = await ToolDiscovery.scan(summarize: false)
        let names = tools.map { $0.name }
        XCTAssertTrue(names.contains("git"))
        XCTAssertTrue(names.contains("swift"))
    }

    func testNoDuplicateNames() async {
        let tools = await ToolDiscovery.scan(summarize: false)
        let names = tools.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count)
    }

    func testCachedScanReusesExistingCache() async throws {
        let root = temporaryDirectory()
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(named: "alpha", in: bin)
        let cacheURL = root.appendingPathComponent("cache.json")

        let first = await ToolDiscovery.cachedScan(
            summarize: false,
            cacheURL: cacheURL,
            pathOverride: bin.path
        )
        XCTAssertEqual(first.map(\.name), ["alpha"])

        try writeExecutable(named: "beta", in: bin)
        let second = await ToolDiscovery.cachedScan(
            summarize: false,
            cacheURL: cacheURL,
            pathOverride: bin.path
        )

        XCTAssertEqual(second.map(\.name), ["alpha"],
                       "A broad discovery call should reuse the cache instead of rescanning PATH")
    }

    func testCachedScanRescansWhenRequestedToolIsMissingFromCache() async throws {
        let root = temporaryDirectory()
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(named: "alpha", in: bin)
        let cacheURL = root.appendingPathComponent("cache.json")

        _ = await ToolDiscovery.cachedScan(summarize: false, cacheURL: cacheURL, pathOverride: bin.path)

        try writeExecutable(named: "beta", in: bin)
        let beta = await ToolDiscovery.cachedScan(
            requestedTool: "beta",
            summarize: false,
            cacheURL: cacheURL,
            pathOverride: bin.path
        )

        XCTAssertEqual(beta.map(\.name), ["beta"])
    }

    func testCachedScanRescansWhenRequestedToolPathIsGone() async throws {
        let root = temporaryDirectory()
        let bin1 = root.appendingPathComponent("bin1", isDirectory: true)
        let bin2 = root.appendingPathComponent("bin2", isDirectory: true)
        try FileManager.default.createDirectory(at: bin1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin2, withIntermediateDirectories: true)
        let alpha1 = try writeExecutable(named: "alpha", in: bin1)
        let cacheURL = root.appendingPathComponent("cache.json")
        let path = "\(bin1.path):\(bin2.path)"

        let first = await ToolDiscovery.cachedScan(
            requestedTool: "alpha",
            summarize: false,
            cacheURL: cacheURL,
            pathOverride: path
        )
        XCTAssertEqual(first.first?.path, alpha1.path)

        try FileManager.default.removeItem(at: alpha1)
        let alpha2 = try writeExecutable(named: "alpha", in: bin2)
        let second = await ToolDiscovery.cachedScan(
            requestedTool: "alpha",
            summarize: false,
            cacheURL: cacheURL,
            pathOverride: path
        )

        XCTAssertEqual(second.first?.path, alpha2.path)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-tool-discovery-\(UUID().uuidString)", isDirectory: true)
    }

    @discardableResult
    private func writeExecutable(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
