import SwiftUI
import FirebaseCore

@main
struct AnalyticsAuditorApp: App {
    init() {
        // Reads GoogleService-Info.plist from the app bundle and starts Firebase.
        FirebaseApp.configure()
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
