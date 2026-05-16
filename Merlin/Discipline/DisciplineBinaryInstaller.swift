import Foundation

/// Copies the bundled `merlin-discipline` executable into ~/.merlin/bin so installed
/// git hooks can find it by absolute path.
enum DisciplineBinaryInstaller {

    enum InstallError: Error, Sendable {
        case bundledBinaryMissing
    }

    static func install() async throws -> String {
        let source = try bundledBinaryURL()
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".merlin/bin/merlin-discipline")
        let parent = destination.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: nil
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destination.path
        )
        return destination.path
    }

    private static func bundledBinaryURL() throws -> URL {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "merlin-discipline"),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        let candidates = [
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Executables/merlin-discipline"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/merlin-discipline"),
            Bundle.main.resourceURL?
                .appendingPathComponent("merlin-discipline")
        ].compactMap { $0 }

        guard let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw InstallError.bundledBinaryMissing
        }
        return match
    }
}
