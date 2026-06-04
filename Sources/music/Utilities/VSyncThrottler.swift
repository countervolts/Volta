import UIKit

@MainActor
final class VSyncThrottler: NSObject {
    private var displayLink: CADisplayLink?
    private let update: @MainActor () -> Void

    init(update: @escaping @MainActor () -> Void) {
        self.update = update
    }

    func schedule() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        invalidate()
        update()
    }

    deinit {
        displayLink?.invalidate()
    }
}
