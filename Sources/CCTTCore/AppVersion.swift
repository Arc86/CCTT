import Foundation

/// Resolves the version string to display: the bundle's marketing version when
/// running as a packaged `.app`, else the compiled-in `coreVersion` (dev runs
/// via `swift run`/`run.sh` have no Info.plist).
public enum AppVersion {
    public static func string(bundleShort: String?) -> String {
        bundleShort ?? coreVersion
    }
}
