import SwiftUI

struct PlaybackActionToast: View {
    let message: String

    private var isPlayingNext: Bool {
        message.localizedCaseInsensitiveCompare("Playing Next") == .orderedSame
    }

    var body: some View {
        HStack(spacing: 12) {
            if isPlayingNext {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 18, weight: .semibold))
            }
            Text(isPlayingNext ? "Playing Next" : message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .accessibilityLabel(isPlayingNext ? "Playing Next" : message)
    }
}
