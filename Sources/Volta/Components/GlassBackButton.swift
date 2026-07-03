import SwiftUI
import UIKit

// Back affordance that keeps edge-swipe intact.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> _VC { _VC() }
    func updateUIViewController(_ v: _VC, context: Context) {
        v.scheduleApplyGesture()
    }

    final class _VC: UIViewController {
        private let popDelegate = PopGestureDelegate()

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            scheduleApplyGesture()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            scheduleApplyGesture()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scheduleApplyGesture()
        }

        func scheduleApplyGesture() {
            DispatchQueue.main.async { [weak self] in
                self?.applyGesture()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.applyGesture()
            }
        }

        private func applyGesture() {
            guard let navigationController = resolvedNavigationController(),
                  let gesture = navigationController.interactivePopGestureRecognizer else { return }
            popDelegate.navigationController = navigationController
            gesture.isEnabled = true
            gesture.delegate = popDelegate
        }

        private func resolvedNavigationController() -> UINavigationController? {
            if let navigationController { return navigationController }
            guard let root = view.window?.rootViewController else { return nil }
            return Self.visibleNavigationController(in: root)
        }

        private static func visibleNavigationController(in viewController: UIViewController) -> UINavigationController? {
            if let presented = viewController.presentedViewController {
                return visibleNavigationController(in: presented)
            }
            if let navigationController = viewController as? UINavigationController {
                return navigationController
            }
            if let tabController = viewController as? UITabBarController,
               let selected = tabController.selectedViewController {
                return visibleNavigationController(in: selected)
            }
            for child in viewController.children.reversed() {
                if let navigationController = visibleNavigationController(in: child) {
                    return navigationController
                }
            }
            return nil
        }
    }

    final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let nav = navigationController else { return false }
            return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gestureRecognizer === navigationController?.interactivePopGestureRecognizer
        }
    }
}

struct GlassBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            // Clear focused search fields first so one tap still goes back.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            DispatchQueue.main.async {
                dismiss()
            }
        } label: {
            Image(systemName: Symbols.back)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 38, height: 38)
                .glassCircle()
        }
        .buttonStyle(.plain)
    }
}
