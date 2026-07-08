import Intents
import UIKit

@MainActor
final class VoltaAppDelegate: NSObject, UIApplicationDelegate {
    private let siriMediaIntentHandler = SiriMediaIntentHandler()

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        if intent is INPlayMediaIntent {
            return siriMediaIntentHandler
        }
        return nil
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppState.shared.persistPlaybackSession()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppState.shared.persistPlaybackSession()
    }
}
