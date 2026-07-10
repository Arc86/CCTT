import CCTTCore
import SwiftUI

// MARK: Environment plumbing

private struct SoftwareUpdaterKey: EnvironmentKey {
    // Computed (not a stored global) so Swift 6 doesn't flag a non-Sendable
    // mutable global: each access constructs a fresh inert `DisabledUpdater`.
    static var defaultValue: any SoftwareUpdating { DisabledUpdater() }
}
private struct LoginItemKey: EnvironmentKey {
    static var defaultValue: any LoginItemControlling { SystemLoginItem() }
}

extension EnvironmentValues {
    var softwareUpdater: any SoftwareUpdating {
        get { self[SoftwareUpdaterKey.self] }
        set { self[SoftwareUpdaterKey.self] = newValue }
    }
    var loginItem: any LoginItemControlling {
        get { self[LoginItemKey.self] }
        set { self[LoginItemKey.self] = newValue }
    }
}

/// General settings: start-at-login and auto-update controls. Both degrade to a
/// disabled state with an explanatory caption when the app runs unbundled.
struct GeneralPane: View {
    @Environment(\.softwareUpdater) private var updater
    @Environment(\.loginItem) private var loginItem

    private var bundled: Bool { AppBundling.isBundled(Bundle.main.bundleURL) }

    @State private var startAtLogin = false
    @State private var autoCheck = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start CCTT at login", isOn: $startAtLogin)
                    .disabled(!bundled)
                    .onChange(of: startAtLogin) { _, want in
                        let actual = LoginItemToggle(loginItem).apply(desired: want)
                        if actual != want {
                            startAtLogin = actual
                            loginError = "macOS declined the login-item change."
                        } else {
                            loginError = nil
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $autoCheck)
                    .disabled(!bundled)
                    .onChange(of: autoCheck) { _, on in
                        updater.automaticallyChecksForUpdates = on
                    }
                HStack {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!bundled || !updater.canCheckForUpdates)
                    Spacer()
                    Text("CCTT v\(AppVersion.string(bundleShort: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !bundled {
                    Text("Updates and login are available in the installed app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            startAtLogin = loginItem.isEnabled
            autoCheck = updater.automaticallyChecksForUpdates
        }
    }
}

#Preview {
    GeneralPane()
        .frame(width: 520, height: 360)
}
