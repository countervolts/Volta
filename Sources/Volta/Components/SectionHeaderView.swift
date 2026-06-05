import SwiftUI

struct SectionHeaderView: View {
    let title: String
    var onSeeAll: (() -> Void)?

    init(_ title: String, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.onSeeAll = onSeeAll
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 12)

            if let onSeeAll {
                Button(action: onSeeAll) {
                    Image(systemName: Symbols.chevron)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 30, height: 30)
                        .glassCircle()
                }
                .buttonStyle(.plain)
            }
        }
    }
}
