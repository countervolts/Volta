import Intents
import UIKit

final class VoltaAppDelegate: NSObject, UIApplicationDelegate {
    private let siriMediaIntentHandler = SiriMediaIntentHandler()

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        if intent is INPlayMediaIntent {
            return siriMediaIntentHandler
        }
        return nil
    }
}

