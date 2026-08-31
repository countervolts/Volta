import Intents
import UIKit

@MainActor
final class VoltaAppDelegate: NSObject, UIApplicationDelegate {
    private let siriMediaIntentHandler = SiriMediaIntentHandler()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CrashReportingService.shared.startIfEnabled()
        CrashHangReporter.shared.start()
        return true
    }

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        if intent is INPlayMediaIntent {
            return siriMediaIntentHandler
        }
        return nil
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        CrashHangReporter.shared.endForegroundMonitoring()
        AppState.shared.persistPlaybackSession()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        CrashHangReporter.shared.beginForegroundMonitoring()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        CrashHangReporter.shared.pauseForegroundMonitoring()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        CrashHangReporter.shared.pauseForegroundMonitoring()
        AppState.shared.persistPlaybackSession()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        CrashHangReporter.shared.recordMemoryWarning()
    }
}
