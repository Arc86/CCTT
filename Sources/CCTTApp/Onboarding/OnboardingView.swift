import SwiftUI
import CCTTCore

/// Whether first-launch onboarding has been completed. A tiny `UserDefaults`
/// flag; the app opens the onboarding window once until this is set.
enum OnboardingState {
    static let key = "cctt.hasOnboarded.v1"
    static func hasOnboarded(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
    static func markOnboarded(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }
}

/// First-launch explainer for the opt-in live-limit feature. Enabling turns on
/// live fetching (the first fetch prompts for Keychain access); declining leaves
/// the app on clearly-labeled estimates, re-enableable later in Settings.
struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(UsageStore.self) private var usage
    @Environment(PlanStore.self) private var planStore
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Brand.logo
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading) {
                    Text("Welcome to CCTT").font(.title2.bold())
                    Text("Your Claude Code token tracker").foregroundStyle(.secondary)
                }
            }

            Text("CCTT reads Claude Code's local usage logs to show how close you are to "
                 + "your plan limits and where your tokens go — entirely on-device and "
                 + "read-only.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Live limits (optional)", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                    Text("Turn this on to fetch real limit percentages and reset times using "
                         + "Claude Code's existing sign-in (read from your Keychain). Without "
                         + "it, CCTT shows honest, clearly-labeled estimates. You can change "
                         + "this any time in Settings.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack {
                Button("Use estimates for now") { finish(enableLive: false) }
                Spacer()
                Button("Enable live limits") { finish(enableLive: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func finish(enableLive: Bool) {
        settingsStore.settings.liveLimitsEnabled = enableLive
        OnboardingState.markOnboarded()
        dismissWindow(id: "onboarding")
        // Trigger the Keychain read now (not on the next poll) so the prompt
        // appears while the user is still in the opt-in flow.
        if enableLive { LiveLimitsActivation.kick(planStore, usage) }
    }
}
