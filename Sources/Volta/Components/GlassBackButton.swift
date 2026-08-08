import SwiftUI
import UIKit

// Back affordance that keeps edge-swipe intact.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    var onNavigationWillAppear: (() -> Void)? = nil
    var onNavigationWillDisappear: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> _VC { _VC() }
    func updateUIViewController(_ v: _VC, context: Context) {
        v.onNavigationWillAppear = onNavigationWillAppear
        v.onNavigationWillDisappear = onNavigationWillDisappear
        v.scheduleApplyGestureIfNeeded()
    }

    final class _VC: UIViewController {
        private let popDelegate = PopGestureDelegate()
        private var didApplyForCurrentLayoutCycle = false
        private var pendingImmediateApply = false
        private var pendingDelayedApply = false
        var onNavigationWillAppear: (() -> Void)?
        var onNavigationWillDisappear: (() -> Void)?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            onNavigationWillAppear?()
            didApplyForCurrentLayoutCycle = false
            scheduleApplyGesture(force: true)
            scheduleDelayedApply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // An interrupted interactive pop returns to this view without a
            // new navigation push. Keep its controls available in that case.
            onNavigationWillAppear?()
            scheduleApplyGesture(force: true)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onNavigationWillDisappear?()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard !didApplyForCurrentLayoutCycle else { return }
            didApplyForCurrentLayoutCycle = true
            scheduleApplyGesture(force: true)
        }

        func scheduleApplyGestureIfNeeded() {
            scheduleApplyGesture(force: false)
        }

        private func scheduleApplyGesture(force: Bool) {
            guard force || !isGestureApplied else { return }
            guard !pendingImmediateApply else { return }
            pendingImmediateApply = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingImmediateApply = false
                self.applyGesture(force: force)
            }
        }

        private func scheduleDelayedApply() {
            guard !pendingDelayedApply else { return }
            pendingDelayedApply = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                self.pendingDelayedApply = false
                self.applyGesture(force: true)
            }
        }

        private var isGestureApplied: Bool {
            guard let navigationController = resolvedNavigationController(),
                  let gesture = navigationController.interactivePopGestureRecognizer else { return false }
            return gesture.isEnabled
                && gesture.delegate === popDelegate
                && popDelegate.navigationController === navigationController
        }

        private func applyGesture(force: Bool) {
            guard let navigationController = resolvedNavigationController(),
                  let gesture = navigationController.interactivePopGestureRecognizer else { return }
            guard force || !isGestureApplied else { return }
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
