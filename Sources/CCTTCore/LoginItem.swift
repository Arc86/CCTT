/// Abstraction over the OS login-item registration so the toggle behaviour is
/// testable without touching `SMAppService`. The concrete `SystemLoginItem`
/// lives in the App target.
public protocol LoginItemControlling {
    /// The system's current registration state (the single source of truth).
    var isEnabled: Bool { get }
    /// Register (true) or unregister (false); throws on OS failure.
    func setEnabled(_ enabled: Bool) throws
}

/// Applies a desired login-item state, reporting the *actual* resulting state so
/// the UI never shows a toggle position the system didn't accept.
public struct LoginItemToggle {
    private let control: any LoginItemControlling
    public init(_ control: any LoginItemControlling) { self.control = control }

    /// Attempts to reach `desired`. Returns the actual state afterwards: on
    /// success that is `desired`; on failure the unchanged `control.isEnabled`.
    public func apply(desired: Bool) -> Bool {
        do {
            try control.setEnabled(desired)
            return desired
        } catch {
            return control.isEnabled
        }
    }
}
