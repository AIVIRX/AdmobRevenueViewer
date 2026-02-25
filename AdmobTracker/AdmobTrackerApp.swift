import SwiftUI
import GoogleSignIn

@main
@MainActor
struct AdmobTrackerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var environment = AppEnvironment(authManager: AuthManager())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(environment)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
