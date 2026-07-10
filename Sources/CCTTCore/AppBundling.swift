import Foundation

/// Whether the running executable lives inside a `.app` bundle. The login-item
/// and updater features require a real bundle; when this is false the UI
/// disables those controls rather than lying or crashing.
public enum AppBundling {
    public static func isBundled(_ bundleURL: URL) -> Bool {
        bundleURL.pathExtension == "app"
    }
}
