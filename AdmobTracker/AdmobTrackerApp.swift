import SwiftUI

@main
@MainActor
struct AdmobTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var appState = AppState()
    @StateObject private var environment = AppEnvironment(authManager: AuthManager())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(environment)
        }
    }
}
