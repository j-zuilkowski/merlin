import Foundation

private final class BundleModuleToken {}

extension Bundle {
    static var module: Bundle {
        Bundle(for: BundleModuleToken.self)
    }
}
