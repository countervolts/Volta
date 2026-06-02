import SwiftUI
import UIKit

// Re-enables interactivePopGestureRecognizer when navigationBarHidden=true prevents swipe-back.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> _VC { _VC() }
    func updateUIViewController(_ v: _VC, context: Context) {}

    final class _VC: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
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
