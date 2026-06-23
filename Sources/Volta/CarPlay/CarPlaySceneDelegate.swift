#if canImport(CarPlay)
import CarPlay
import UIKit

// Scene delegate for the CarPlay template scene. Named in Info.plist as
// `Volta.CarPlaySceneDelegate` (UISceneDelegateClassName). UIKit instantiates it
// when CarPlay attaches and hands us the interface controller to drive.
//
// CarPlay scene callbacks always arrive on the main thread, so we hop onto the
// main actor to reach the (@MainActor) CarPlayController.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        MainActor.assumeIsolated {
            CarPlayController.shared.connect(interfaceController)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        MainActor.assumeIsolated {
            CarPlayController.shared.disconnect()
        }
    }
}
#endif
