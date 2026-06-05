import SwiftUI

// placeholder for StatsView only - LibraryView, PlaylistsView, StatsView all
// get full implementations in their own files.
private struct PlaceholderContent: View {
    let title: String
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}
