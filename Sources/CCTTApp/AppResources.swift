import Foundation

/// Resolves the app's SwiftPM resource bundle (`CCTT_CCTTApp.bundle`, holding the
/// brand image assets) in a way that works in the packaged, code-signed `.app`.
///
/// The compiler-generated `Bundle.module` accessor only looks for the resource
/// bundle at `Bundle.main.bundleURL/CCTT_CCTTApp.bundle`. For a packaged `.app`
/// that path is the bundle *root* (`CCTT.app/CCTT_CCTTApp.bundle`) — but resources
/// at the `.app` root cannot be sealed by `codesign` (`codesign --verify --strict`
/// reports "unsealed contents present in the bundle root" and notarization rejects
/// it). So `packaging/package_app.sh` places the bundle under `Contents/Resources`,
/// the standard code-signable location — where `Bundle.module` never looks. The
/// result was a hard trap on every launch:
///
///     Fatal error: could not load resource bundle: from …/CCTT.app/CCTT_CCTTApp.bundle
///
/// This resolver searches locations relative to `Bundle.main` instead:
///   1. `Bundle.main.resourceURL` — the packaged app's `Contents/Resources`.
///   2. `Bundle.main.bundleURL`  — the executable's own directory under
///      `swift build` / `swift run`, where SwiftPM drops the bundle beside the binary.
///
/// This keeps the dev workflow working while fixing the packaged app.
enum AppResources {
    /// The bundle containing the brand image assets. Falls back to `Bundle.main`
    /// if the resource bundle can't be located; asset lookups are non-critical
    /// (callers degrade to an SF Symbol), so this stays non-fatal by design.
    static let bundle: Bundle = {
        let name = "CCTT_CCTTApp.bundle"
        let searchBases = [Bundle.main.resourceURL, Bundle.main.bundleURL]
        for base in searchBases {
            if let url = base?.appendingPathComponent(name),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .main
    }()
}
