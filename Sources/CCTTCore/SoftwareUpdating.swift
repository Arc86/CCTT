/// Abstraction over the auto-updater so views can be built and previewed
/// without Sparkle, and so unbundled runs stay inert. The concrete
/// `SparkleUpdater` lives in the App target.
public protocol SoftwareUpdating: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}

/// Used when the app runs unbundled (no Sparkle framework): every control is
/// inert and the UI presents them disabled.
public final class DisabledUpdater: SoftwareUpdating {
    public init() {}
    public var canCheckForUpdates: Bool { false }
    public var automaticallyChecksForUpdates: Bool = false
    public func checkForUpdates() {}
}
