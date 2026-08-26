import SwiftUI
import GoogleSignIn

@main
@MainActor
struct AdmobTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @StateObject private var environment = AppEnvironment(authManager: AuthManager())

    init() {
        WidgetBackgroundRefreshCoordinator.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(environment)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                WidgetBackgroundRefreshCoordinator.schedule()
            }
        }
    }
}
