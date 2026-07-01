import SwiftUI
import UIKit

// Back affordance that keeps edge-swipe intact.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> _VC { _VC() }
    func updateUIViewController(_ v: _VC, context: Context) {}

    final class _VC: UIViewController {
        private let popDelegate = PopGestureDelegate()

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyGesture()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyGesture()
        }

        private func applyGesture() {
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            popDelegate.navigationController = navigationController
            gesture.isEnabled = true
            gesture.delegate = popDelegate
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
            false
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
