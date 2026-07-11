import AppIntents
import SwiftUI

@main
struct VoltaApp: App {
    @UIApplicationDelegateAdaptor(VoltaAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    init() {
        VoltaShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
