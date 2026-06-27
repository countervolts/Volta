import SwiftUI

struct SectionHeaderView: View {
    let title: String
    var onSeeAll: (() -> Void)?

    init(_ title: String, onSeeAll: (() -> Void)? = nil) {
        self.title = title
        self.onSeeAll = onSeeAll
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            if let onSeeAll {
                Button(action: onSeeAll) {
                    Image(systemName: Symbols.chevron)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L(.a11y_see_all, title))
            }

            Spacer(minLength: 0)
        }
    }
}
