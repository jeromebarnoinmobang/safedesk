import SwiftUI

@main
struct SafeDeskApp: App {
    @StateObject private var config = Config()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(config)
                .onOpenURL { url in _ = config.apply(code: url.absoluteString) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var config: Config
    var body: some View {
        if config.isConfigured { DesktopView() } else { OnboardingView() }
    }
}