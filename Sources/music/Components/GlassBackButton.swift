import SwiftUI
import UIKit

// Re-enables interactivePopGestureRecognizer when navigationBarHidden=true would
// otherwise disable swipe-back.
//
// The earlier version set the recognizer's delegate to nil. That removed UIKit's
// gating entirely, so the pop gesture could (a) begin while a push/pop was still
// animating and (b) fire simultaneously with the scroll view's pan. Paired with the
// `.zoom` navigation transition that left the matched source artwork as an orphaned
// snapshot which then scrolled with the list — the "detached album cover" bug.
//
// A real delegate restores proper gating: begin only off the root and when no
// transition is in flight, and never run alongside another gesture.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> _VC { _VC() }
    func updateUIViewController(_ v: _VC, context: Context) {}

    final class _VC: UIViewController {
        // strongly held so it stays alive as this controller's pop-gesture delegate
        private let popDelegate = PopGestureDelegate()

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
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
            // not at the root, and not while a push/pop is still animating (mid-transition
            // is exactly when the zoom source snapshot gets orphaned)
            return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
        }

        // never recognise together with the scroll view's pan — running both at once
        // is what dragged the orphaned cover snapshot along with the scroll
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
// liquid glass circular back button for pushed views.
struct GlassBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
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
