import Foundation

/// SwiftPM's executable accessor checks the .app root, whereas macOS
/// packaging places resources in Contents/Resources. Never probe the source
/// checkout when a self-contained packaged resource bundle is available.
enum NativeResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "DynamicIsland_LibrariesNative", withExtension: "bundle"),
           let packaged = Bundle(url: url) {
            return packaged
        }
        return Bundle.module
    }()
}
